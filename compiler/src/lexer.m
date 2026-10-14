% SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
% Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
% Authored by Ahmad Ali Parr.
% Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

%---------------------------------------------------------------------------%
% lexer.m
%
% Tokenizer shared by the Mercury circuit source language and the OpenQASM 3
% subset.
%
% Purpose:    Turn source text into located tokens.
% Inputs:     A string of source text.
% Outputs:    A list of located tokens ending in tok_eof, or the first
%             lexical error with its location.
% Semantics:  Identifiers, decimal integers, reals (optional exponent),
%             double-quoted strings, the punctuation set of
%             specifications/compiler/SOURCE_LANGUAGE.md, `//` and `/* */`
%             comments. Lines and columns are 1-based.
% Failures:   Unterminated block comment or string, unexpected character,
%             malformed real or integer literal.
%
%---------------------------------------------------------------------------%

:- module lexer.
:- interface.

:- import_module circuit.
:- import_module list.

%---------------------------------------------------------------------------%

:- type token
    --->    tok_ident(string)
    ;       tok_int(int)
    ;       tok_real(float)
    ;       tok_string(string)
    ;       tok_sym(string)
    ;       tok_eof.

:- type ltok
    --->    ltok(ltok_token :: token, ltok_loc :: loc).

:- type lex_error
    --->    lex_error(lex_loc :: loc, lex_msg :: string).

:- type lex_result
    --->    lex_ok(list(ltok))
    ;       lex_err(lex_error).

:- pred tokenize(string::in, lex_result::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module char.
:- import_module int.
:- import_module string.

tokenize(Text, Result) :-
    string.to_char_list(Text, Chars),
    lex(Chars, loc(1, 1), [], Result).

:- pred lex(list(char)::in, loc::in, list(ltok)::in, lex_result::out) is det.

lex([], Loc, Acc, lex_ok(Tokens)) :-
    Tokens = list.reverse([ltok(tok_eof, Loc) | Acc]).
lex([C | Cs], Loc, Acc, Result) :-
    classify(C, Cs, Class),
    lex_class(Class, C, Cs, Loc, Acc, Result).

:- type cclass
    --->    c_space
    ;       c_line_comment
    ;       c_block_comment
    ;       c_ident
    ;       c_number
    ;       c_string
    ;       c_symbol
    ;       c_bad.

:- pred classify(char::in, list(char)::in, cclass::out) is det.

classify(C, Rest, Class) :-
    ( if is_space(C) then
        Class = c_space
    else if line_comment_start(C, Rest) then
        Class = c_line_comment
    else if block_comment_start(C, Rest) then
        Class = c_block_comment
    else if char.is_alpha(C) then
        Class = c_ident
    else if C = '_' then
        Class = c_ident
    else if char.is_digit(C) then
        Class = c_number
    else if dot_then_digit(C, Rest) then
        Class = c_number
    else if C = '"' then
        Class = c_string
    else if is_symbol(C) then
        Class = c_symbol
    else
        Class = c_bad
    ).

:- pred is_space(char::in) is semidet.

is_space(' ').
is_space('\t').
is_space('\n').
is_space('\r').

:- pred line_comment_start(char::in, list(char)::in) is semidet.

line_comment_start('/', ['/' | _]).

:- pred block_comment_start(char::in, list(char)::in) is semidet.

block_comment_start('/', ['*' | _]).

% Longest prefix of Chars satisfying P, and the remainder.
:- pred take_chars(pred(char)::in(pred(in) is semidet), list(char)::in,
    list(char)::out, list(char)::out) is det.

take_chars(_, [], [], []).
take_chars(P, [C | Cs], Taken, Rest) :-
    ( if P(C) then
        take_chars(P, Cs, Taken0, Rest),
        Taken = [C | Taken0]
    else
        Taken = [],
        Rest = [C | Cs]
    ).

:- pred dot_then_digit(char::in, list(char)::in) is semidet.

dot_then_digit('.', [D | _]) :-
    char.is_digit(D).

:- pred is_symbol(char::in) is semidet.

is_symbol('[').
is_symbol(']').
is_symbol('(').
is_symbol(')').
is_symbol('{').
is_symbol('}').
is_symbol(',').
is_symbol(';').
is_symbol('=').
is_symbol('*').
is_symbol('/').
is_symbol('-').
is_symbol('+').

:- pred lex_class(cclass::in, char::in, list(char)::in, loc::in,
    list(ltok)::in, lex_result::out) is det.

lex_class(c_space, C, Cs, Loc, Acc, Result) :-
    advance(C, Loc, Loc1),
    lex(Cs, Loc1, Acc, Result).
lex_class(c_line_comment, _, Cs, Loc, Acc, Result) :-
    skip_line(Cs, Loc, Rest, Loc1),
    lex(Rest, Loc1, Acc, Result).
lex_class(c_block_comment, _, Cs0, Loc, Acc, Result) :-
    % classify/3 has matched the "/*" pair, so Cs0 starts with '*'. Drop it,
    % then scan to the closing "*/".
    ( if Cs0 = [_ | Cs1] then
        skip_block(Cs1, loc(Loc^line, Loc^col + 2), Loc, Rest, Loc1, MaybeErr),
        (
            MaybeErr = yes(Err),
            Result = lex_err(Err)
        ;
            MaybeErr = no,
            lex(Rest, Loc1, Acc, Result)
        )
    else
        Result = lex_err(lex_error(Loc, "unterminated block comment"))
    ).
lex_class(c_ident, C, Cs, Loc, Acc, Result) :-
    take_chars(is_ident_char, [C | Cs], Taken, Rest),
    string.from_char_list(Taken, Word),
    Loc1 = loc(Loc^line, Loc^col + list.length(Taken)),
    lex(Rest, Loc1, [ltok(tok_ident(Word), Loc) | Acc], Result).
lex_class(c_number, C, Cs, Loc, Acc, Result) :-
    lex_number([C | Cs], Loc, Acc, Result).
lex_class(c_string, _, Cs, Loc, Acc, Result) :-
    take_chars(is_not_quote_or_newline, Cs, Body, Rest0),
    ( if closing_quote(Rest0, Rest) then
        string.from_char_list(Body, Text),
        Loc1 = loc(Loc^line, Loc^col + list.length(Body) + 2),
        lex(Rest, Loc1, [ltok(tok_string(Text), Loc) | Acc], Result)
    else
        Result = lex_err(lex_error(Loc, "unterminated string literal"))
    ).
lex_class(c_symbol, C, Cs, Loc, Acc, Result) :-
    Sym = string.from_char(C),
    lex(Cs, loc(Loc^line, Loc^col + 1), [ltok(tok_sym(Sym), Loc) | Acc],
        Result).
lex_class(c_bad, C, _, Loc, _, lex_err(lex_error(Loc, Msg))) :-
    S = string.from_char(C),
    Msg = "unexpected character '" ++ S ++ "'".

:- pred is_ident_char(char::in) is semidet.

is_ident_char(C) :-
    ( char.is_alnum(C)
    ; C = '_'
    ).

:- pred closing_quote(list(char)::in, list(char)::out) is semidet.

closing_quote(['"' | Rest], Rest).

:- pred is_not_quote_or_newline(char::in) is semidet.

is_not_quote_or_newline(C) :-
    C \= '"',
    C \= '\n'.

:- pred advance(char::in, loc::in, loc::out) is det.

advance(C, loc(L, Col), loc(L1, Col1)) :-
    ( if C = '\n' then
        L1 = L + 1,
        Col1 = 1
    else if C = '\t' then
        L1 = L,
        Col1 = ((Col - 1) // 8 + 1) * 8 + 1
    else
        L1 = L,
        Col1 = Col + 1
    ).

:- pred skip_line(list(char)::in, loc::in, list(char)::out, loc::out) is det.

skip_line(Cs, loc(L, Col), Rest, Loc1) :-
    take_chars(is_not_newline, Cs, Skipped, Rest0),
    (
        Rest0 = [ _ | Rest1 ],
        Rest = Rest1,
        Loc1 = loc(L + 1, 1)
    ;
        Rest0 = [],
        Rest = [],
        Loc1 = loc(L, Col + list.length(Skipped))
    ).

:- pred is_not_newline(char::in) is semidet.

is_not_newline(C) :-
    C \= '\n'.

% Skip to the closing "*/". Start is the location of the first character after
% the "/*" pair; Open is the location of the opening slash.
:- pred skip_block(list(char)::in, loc::in, loc::in, list(char)::out,
    loc::out, maybe_err::out) is det.

:- type maybe_err
    --->    no
    ;       yes(lex_error).

skip_block([], _, Open, [], Open,
    yes(lex_error(Open, "unterminated block comment"))).
skip_block([C | Cs], Loc, Open, Rest, Loc1, Err) :-
    ( if close_comment(C, Cs, AfterClose) then
        Rest = AfterClose,
        Loc1 = loc(Loc^line, Loc^col + 2),
        Err = no
    else
        advance(C, Loc, Loc0),
        skip_block(Cs, Loc0, Open, Rest, Loc1, Err)
    ).

:- pred close_comment(char::in, list(char)::in, list(char)::out) is semidet.

close_comment('*', ['/' | Rest], Rest).

:- pred lex_number(list(char)::in, loc::in, list(ltok)::in,
    lex_result::out) is det.

lex_number(Chars, Loc, Acc, Result) :-
    take_chars(is_mantissa_char, Chars, Mantissa, Rest0),
    take_exponent(Rest0, Exponent, Rest),
    Taken = Mantissa ++ Exponent,
    string.from_char_list(Taken, Text),
    Loc1 = loc(Loc^line, Loc^col + list.length(Taken)),
    ( if string.all_match(char.is_digit, Text) then
        ( if string.to_int(Text, N) then
            lex(Rest, Loc1, [ltok(tok_int(N), Loc) | Acc], Result)
        else
            Result = lex_err(lex_error(Loc, "integer literal out of range"))
        )
    else
        ( if string.to_float(Text, F) then
            lex(Rest, Loc1, [ltok(tok_real(F), Loc) | Acc], Result)
        else
            Result = lex_err(lex_error(Loc,
                "malformed real literal '" ++ Text ++ "'"))
        )
    ).

:- pred is_mantissa_char(char::in) is semidet.

is_mantissa_char(C) :-
    ( char.is_digit(C)
    ; list.member(C, ['.'])
    ).

% An optional exponent: 'e' or 'E', an optional sign, then digits. The sign
% is part of the literal only here, so "2+3" lexes as three tokens.
:- pred take_exponent(list(char)::in, list(char)::out, list(char)::out)
    is det.

take_exponent(Cs, Exponent, Rest) :-
    ( if Cs = [E | R0], is_exponent_marker(E) then
        ( if R0 = [S | R1], is_sign(S) then
            SignPart = [S],
            R2 = R1
        else
            SignPart = [],
            R2 = R0
        ),
        take_chars(char.is_digit, R2, Digits, Rest1),
        ( if Digits = [] then
            % No exponent digits: leave the marker for the caller, so that
            % "1e" is reported rather than read as 1.
            Exponent = [],
            Rest = Cs
        else
            Exponent = [E] ++ SignPart ++ Digits,
            Rest = Rest1
        )
    else
        Exponent = [],
        Rest = Cs
    ).

:- pred is_exponent_marker(char::in) is semidet.

is_exponent_marker('e').
is_exponent_marker('E').

:- pred is_sign(char::in) is semidet.

is_sign('+').
is_sign('-').

%---------------------------------------------------------------------------%
:- end_module lexer.
%---------------------------------------------------------------------------%
