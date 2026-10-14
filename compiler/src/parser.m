% SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
% Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
% Authored by Ahmad Ali Parr.
% Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

%---------------------------------------------------------------------------%
% parser.m
%
% Recursive-descent parser for the Mercury circuit source language and the
% OpenQASM 3 subset in specifications/interchange/QASM_SUBSET.md. The two
% share one grammar: the source language is the subset with an optional
% header.
%
% Purpose:    Build a circuit (circuit.m) from text, with source locations.
% Inputs:     Program text.
% Outputs:    parse_ok(circuit) or parse_fail(diagnostics). Parsing stops at
%             the first syntax error; validate.m reports semantic errors over
%             the whole circuit.
% Semantics:  - Optional header `OPENQASM 3.0;`. Other versions are rejected.
%             - `include "stdgates.inc";` produces no items; any other include
%               is unsupported.
%             - Whole-register operands broadcast: a gate over registers of
%               equal length expands pairwise, an indexed operand stays fixed;
%               `reset q;` resets each qubit; `barrier q;` is one barrier over
%               every qubit of q; `c = measure q;` measures pairwise.
%             - Angles: [-] (number | pi) [ (* | /) (number | pi) ], with the
%               forms listed in specifications/compiler/CIRCUIT_IR.md.
%             - Keywords of unsupported constructs produce E-UNSUPPORTED.
% Failures:   E-LEX, E-SYNTAX, E-UNSUPPORTED, E-UNDECLARED, E-BROADCAST.
%
% Style:      Dispatch is by if-then-else on pattern tests, not by
%             disjunction, so that every branch is exclusive and the
%             predicates are det.
%
%---------------------------------------------------------------------------%

:- module parser.
:- interface.

:- import_module circuit.
:- import_module diagnostic.
:- import_module list.

:- type parse_result
    --->    parse_ok(circuit)
    ;       parse_fail(list(diag)).

:- pred parse_program(string::in, parse_result::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module float.
:- import_module int.
:- import_module lexer.
:- import_module maybe.
:- import_module string.
:- import_module unit.

% A parse step yields a value and the remaining tokens, or a diagnostic.
:- type presult(T)
    --->    pok(T, list(ltok))
    ;       perr(diag).

%---------------------------------------------------------------------------%

parse_program(Text, Result) :-
    tokenize(Text, LexResult),
    (
        LexResult = lex_err(lex_error(Loc, Msg)),
        Result = parse_fail([diag(Loc, "E-LEX", Msg)])
    ;
        LexResult = lex_ok(Toks),
        parse_header(Toks, HeaderResult),
        (
            HeaderResult = perr(D),
            Result = parse_fail([D])
        ;
            HeaderResult = pok(_, Toks1),
            parse_items(Toks1, [], [], ItemsResult),
            (
                ItemsResult = perr(D),
                Result = parse_fail([D])
            ;
                ItemsResult = pok(Items, _),
                Result = parse_ok(circuit(Items))
            )
        )
    ).

%---------------------------------------------------------------------------%
% Header

:- pred parse_header(list(ltok)::in, presult(unit)::out) is det.

parse_header(Toks, Result) :-
    ( if Toks = [ltok(tok_ident("OPENQASM"), Loc) | Rest0] then
        ( if Rest0 = [ltok(tok_real(V), _) | Rest1], V = 3.0 then
            expect_sym(";", Rest1, SemiResult),
            (
                SemiResult = pok(_, Rest2),
                Result = pok(unit, Rest2)
            ;
                SemiResult = perr(D),
                Result = perr(D)
            )
        else
            Result = perr(diag(Loc, "E-UNSUPPORTED",
                "only OpenQASM 3.0 is supported"))
        )
    else
        Result = pok(unit, Toks)
    ).

%---------------------------------------------------------------------------%
% Items: declarations and statements, in source order.
%
% Decls is the declarations seen so far, in declaration order; broadcasts
% resolve register sizes against it. Acc is the items so far, reversed.

:- pred parse_items(list(ltok)::in, list(reg_decl)::in, list(item)::in,
    presult(list(item))::out) is det.

parse_items(Toks, Decls, Acc, Result) :-
    ( if Toks = [] then
        Result = pok(list.reverse(Acc), [])
    else if Toks = [ltok(tok_eof, _)] then
        Result = pok(list.reverse(Acc), [])
    else if Toks = [ltok(tok_ident(Name), Loc) | Rest] then
        parse_item(Name, Loc, Rest, Decls, Acc, Result)
    else if Toks = [ltok(T, Loc) | _] then
        Result = perr(diag(Loc, "E-SYNTAX",
            "expected a declaration or statement, found " ++ describe(T)))
    else
        Result = pok(list.reverse(Acc), [])
    ).

:- pred parse_item(string::in, loc::in, list(ltok)::in, list(reg_decl)::in,
    list(item)::in, presult(list(item))::out) is det.

parse_item(Name, Loc, Rest, Decls, Acc, Result) :-
    ( if Name = "qubit" then
        parse_decl(quantum, Loc, Rest, DeclResult),
        decl_step(DeclResult, Decls, Acc, Result)
    else if Name = "bit" then
        parse_decl(classical, Loc, Rest, DeclResult),
        decl_step(DeclResult, Decls, Acc, Result)
    else if Name = "include" then
        parse_include(Loc, Rest, IncResult),
        (
            IncResult = perr(D),
            Result = perr(D)
        ;
            IncResult = pok(_, Rest1),
            parse_items(Rest1, Decls, Acc, Result)
        )
    else if is_unsupported_keyword(Name) then
        Result = perr(diag(Loc, "E-UNSUPPORTED",
            "unsupported construct '" ++ Name ++ "'"))
    else
        parse_statement(Name, Loc, Rest, Decls, StmtResult),
        (
            StmtResult = perr(D),
            Result = perr(D)
        ;
            StmtResult = pok(Stmts, Rest1),
            Items = list.map(item_of_stmt, Stmts),
            parse_items(Rest1, Decls, list.reverse(Items) ++ Acc, Result)
        )
    ).

:- pred decl_step(presult(reg_decl)::in, list(reg_decl)::in,
    list(item)::in, presult(list(item))::out) is det.

decl_step(perr(D), _, _, perr(D)).
decl_step(pok(Decl, Rest), Decls, Acc, Result) :-
    parse_items(Rest, Decls ++ [Decl], [decl(Decl) | Acc], Result).

:- func item_of_stmt(stmt) = item.

item_of_stmt(S) = op(S).

:- pred is_unsupported_keyword(string::in) is semidet.

is_unsupported_keyword(Kw) :-
    list.member(Kw, [
        "if", "else", "while", "for", "def", "const", "input", "output",
        "gate", "delay", "box", "defcal", "defcalgrammar", "cal", "extern",
        "let", "array", "durationof", "stretch", "measure"
    ]).

:- pred parse_include(loc::in, list(ltok)::in, presult(unit)::out) is det.

parse_include(Loc, Toks, Result) :-
    ( if Toks = [ltok(tok_string("stdgates.inc"), _) | Rest0] then
        expect_sym(";", Rest0, SemiResult),
        (
            SemiResult = pok(_, Rest1),
            Result = pok(unit, Rest1)
        ;
            SemiResult = perr(D),
            Result = perr(D)
        )
    else if Toks = [ltok(tok_string(_), _) | _] then
        Result = perr(diag(Loc, "E-UNSUPPORTED",
            "only include \"stdgates.inc\" is supported"))
    else if Toks = [ltok(T, _) | _] then
        Result = perr(diag(Loc, "E-SYNTAX",
            "expected a string after include, found " ++ describe(T)))
    else
        Result = perr(diag(Loc, "E-SYNTAX",
            "expected a string after include"))
    ).

%---------------------------------------------------------------------------%
% Declarations: qubit[N] name;  or  bit[N] name;   (N defaults to 1)

:- pred parse_decl(reg_kind::in, loc::in, list(ltok)::in,
    presult(reg_decl)::out) is det.

parse_decl(Kind, Loc, Toks, Result) :-
    ( if Toks = [ltok(tok_sym("["), _), ltok(tok_int(N), _),
            ltok(tok_sym("]"), _) | Rest0] then
        Size = N,
        Rest1 = Rest0
    else
        Size = 1,
        Rest1 = Toks
    ),
    ( if Rest1 = [ltok(tok_ident(Name), _) | Rest2] then
        expect_sym(";", Rest2, SemiResult),
        (
            SemiResult = pok(_, Rest3),
            Result = pok(reg_decl(Name, Size, Kind, Loc), Rest3)
        ;
            SemiResult = perr(D),
            Result = perr(D)
        )
    else if Rest1 = [ltok(T, TLoc) | _] then
        Result = perr(diag(TLoc, "E-SYNTAX",
            "expected a register name, found " ++ describe(T)))
    else
        Result = perr(diag(Loc, "E-SYNTAX", "expected a register name"))
    ).

%---------------------------------------------------------------------------%
% Statements. The leading identifier Name has already been consumed.

:- pred parse_statement(string::in, loc::in, list(ltok)::in,
    list(reg_decl)::in, presult(list(stmt))::out) is det.

parse_statement(Name, Loc, Rest, Decls, Result) :-
    ( if Name = "reset" then
        parse_operands(Rest, OpResult),
        (
            OpResult = perr(D),
            Result = perr(D)
        ;
            OpResult = pok(Qrefs, Rest1),
            expand_qrefs(Decls, Loc, Qrefs, ExpResult),
            (
                ExpResult = perr(D),
                Result = perr(D)
            ;
                ExpResult = pok(Qs, _),
                Result = pok(list.map(reset_stmt(Loc), Qs), Rest1)
            )
        )
    else if Name = "barrier" then
        parse_operands(Rest, OpResult),
        (
            OpResult = perr(D),
            Result = perr(D)
        ;
            OpResult = pok(Qrefs, Rest1),
            expand_qrefs(Decls, Loc, Qrefs, ExpResult),
            (
                ExpResult = perr(D),
                Result = perr(D)
            ;
                ExpResult = pok(Qs, _),
                Result = pok([stmt(Loc, barrier(Qs))], Rest1)
            )
        )
    else if gate_from_name(Name, Gate) then
        parse_gate_statement(Gate, Loc, Rest, Decls, Result)
    else
        parse_bit_statement(Name, Loc, Rest, Decls, Result)
    ).

:- func reset_stmt(loc, qref) = stmt.

reset_stmt(Loc, Q) = stmt(Loc, reset(Q)).

% Gate call:  name [ '(' angle ')' ] operand { ',' operand } ';'
:- pred parse_gate_statement(gate_kind::in, loc::in, list(ltok)::in,
    list(reg_decl)::in, presult(list(stmt))::out) is det.

parse_gate_statement(Gate, Loc, Toks, Decls, Result) :-
    ( if Toks = [ltok(tok_sym("("), _) | Rest0] then
        parse_angle(Rest0, AngleResult),
        (
            AngleResult = perr(D),
            Result = perr(D)
        ;
            AngleResult = pok(Angle, Rest1),
            ( if Rest1 = [ltok(tok_sym(")"), _) | Rest2] then
                parse_operands(Rest2, OpResult),
                finish_gate(Gate, [Angle], Loc, Decls, OpResult, Result)
            else if Rest1 = [ltok(T, TLoc) | _] then
                % Anything after a complete angle other than ')' is an
                % expression outside the angle grammar.
                Result = perr(diag(TLoc, "E-UNSUPPORTED",
                    "unsupported angle expression at " ++ describe(T)))
            else
                Result = perr(diag(Loc, "E-SYNTAX",
                    "expected ')' after angle"))
            )
        )
    else
        parse_operands(Toks, OpResult),
        finish_gate(Gate, [], Loc, Decls, OpResult, Result)
    ).

:- pred finish_gate(gate_kind::in, list(float)::in, loc::in,
    list(reg_decl)::in, presult(list(qref))::in,
    presult(list(stmt))::out) is det.

finish_gate(_, _, _, _, perr(D), perr(D)).
finish_gate(Gate, Angles, Loc, Decls, pok(Qrefs, Rest), Result) :-
    expand_gate(Decls, Loc, Gate, Angles, Qrefs, ExpResult),
    (
        ExpResult = perr(D),
        Result = perr(D)
    ;
        ExpResult = pok(Ops, _),
        Result = pok(list.map(stmt_of_op(Loc), Ops), Rest)
    ).

:- func stmt_of_op(loc, op) = stmt.

stmt_of_op(Loc, Op) = stmt(Loc, Op).

% Measurement with a classical destination:
%   c[i] = measure q[j];      c = measure q;
:- pred parse_bit_statement(string::in, loc::in, list(ltok)::in,
    list(reg_decl)::in, presult(list(stmt))::out) is det.

parse_bit_statement(Name, Loc, Toks, Decls, Result) :-
    ( if Toks = [ltok(tok_sym("["), _), ltok(tok_int(I), _),
            ltok(tok_sym("]"), _), ltok(tok_sym("="), _) | Rest0] then
        parse_measure_rhs(Name, I, Loc, Rest0, Decls, Result)
    else if Toks = [ltok(tok_sym("="), _) | Rest0] then
        parse_measure_rhs(Name, -1, Loc, Rest0, Decls, Result)
    else
        Result = perr(diag(Loc, "E-UNSUPPORTED",
            "unsupported statement starting with '" ++ Name ++ "'"))
    ).

:- pred parse_measure_rhs(string::in, int::in, loc::in, list(ltok)::in,
    list(reg_decl)::in, presult(list(stmt))::out) is det.

parse_measure_rhs(Name, Index, Loc, Toks, Decls, Result) :-
    ( if Toks = [ltok(tok_ident("measure"), _) | Rest0] then
        parse_qref(Rest0, QResult),
        (
            QResult = perr(D),
            Result = perr(D)
        ;
            QResult = pok(Src, Rest1),
            expect_sym(";", Rest1, SemiResult),
            (
                SemiResult = perr(D),
                Result = perr(D)
            ;
                SemiResult = pok(_, Rest2),
                expand_measure(Decls, Loc, bref(Name, Index), Src, MResult),
                (
                    MResult = perr(D),
                    Result = perr(D)
                ;
                    MResult = pok(Ops, _),
                    Result = pok(list.map(stmt_of_op(Loc), Ops), Rest2)
                )
            )
        )
    else if Toks = [ltok(T, TLoc) | _] then
        Result = perr(diag(TLoc, "E-SYNTAX",
            "expected 'measure' after '=', found " ++ describe(T)))
    else
        Result = perr(diag(Loc, "E-SYNTAX",
            "expected 'measure' after '='"))
    ).

%---------------------------------------------------------------------------%
% Operands:  qref { ',' qref } ';'

:- pred parse_operands(list(ltok)::in, presult(list(qref))::out) is det.

parse_operands(Toks, Result) :-
    parse_qref(Toks, QResult),
    (
        QResult = perr(D),
        Result = perr(D)
    ;
        QResult = pok(Q, Rest0),
        ( if Rest0 = [ltok(tok_sym(";"), _) | Rest1] then
            Result = pok([Q], Rest1)
        else if Rest0 = [ltok(tok_sym(","), _) | Rest1] then
            parse_operands(Rest1, TailResult),
            (
                TailResult = perr(D),
                Result = perr(D)
            ;
                TailResult = pok(Qs, Rest2),
                Result = pok([Q | Qs], Rest2)
            )
        else if Rest0 = [ltok(T, TLoc) | _] then
            Result = perr(diag(TLoc, "E-SYNTAX",
                "expected ',' or ';' after operand, found " ++ describe(T)))
        else
            Result = perr(diag(loc(0, 0), "E-SYNTAX",
                "unexpected end of input"))
        )
    ).

% qref:  IDENT | IDENT '[' INT ']'
:- pred parse_qref(list(ltok)::in, presult(qref)::out) is det.

parse_qref(Toks, Result) :-
    ( if Toks = [ltok(tok_ident(Name), _), ltok(tok_sym("["), _),
            ltok(tok_int(I), _), ltok(tok_sym("]"), _) | Rest] then
        Result = pok(qref(Name, I), Rest)
    else if Toks = [ltok(tok_ident(Name), _), ltok(tok_sym("["), _) | _] then
        Result = perr(diag(loc(0, 0), "E-SYNTAX",
            "expected an integer index in '" ++ Name ++ "[...]'"))
    else if Toks = [ltok(tok_ident(Name), _) | Rest] then
        Result = pok(qref(Name, -1), Rest)
    else if Toks = [ltok(T, Loc) | _] then
        Result = perr(diag(Loc, "E-SYNTAX",
            "expected a qubit operand, found " ++ describe(T)))
    else
        Result = perr(diag(loc(0, 0), "E-SYNTAX",
            "expected a qubit operand, found end of input"))
    ).

%---------------------------------------------------------------------------%
% Angles

:- type aval
    --->    num(float)
    ;       pi_atom.

% angle := ['-'] atom [ ('*' | '/') atom ]
:- pred parse_angle(list(ltok)::in, presult(float)::out) is det.

parse_angle(Toks, Result) :-
    ( if Toks = [ltok(tok_sym("-"), _) | Rest0] then
        Sign = -1.0,
        Rest1 = Rest0
    else
        Sign = 1.0,
        Rest1 = Toks
    ),
    parse_atom(Rest1, A1Result),
    (
        A1Result = perr(D),
        Result = perr(D)
    ;
        A1Result = pok(A1, Rest2),
        ( if Rest2 = [ltok(tok_sym("*"), Loc) | Rest3] then
            parse_atom(Rest3, A2Result),
            (
                A2Result = perr(D),
                Result = perr(D)
            ;
                A2Result = pok(A2, Rest4),
                combine_times(Loc, A1, A2, Sign, Rest4, Result)
            )
        else if Rest2 = [ltok(tok_sym("/"), Loc) | Rest3] then
            parse_atom(Rest3, A2Result),
            (
                A2Result = perr(D),
                Result = perr(D)
            ;
                A2Result = pok(A2, Rest4),
                combine_divide(Loc, A1, A2, Sign, Rest4, Result)
            )
        else
            Result = pok(Sign * alone_value(A1), Rest2)
        )
    ).

% A bare angle atom: a number, or pi.
:- func alone_value(aval) = float.

alone_value(num(X)) = X.
alone_value(pi_atom) = pi_value.

:- pred parse_atom(list(ltok)::in, presult(aval)::out) is det.

parse_atom(Toks, Result) :-
    ( if Toks = [ltok(tok_int(I), _) | Rest] then
        Result = pok(num(float(I)), Rest)
    else if Toks = [ltok(tok_real(F), _) | Rest] then
        Result = pok(num(F), Rest)
    else if Toks = [ltok(tok_ident("pi"), _) | Rest] then
        Result = pok(pi_atom, Rest)
    else if Toks = [ltok(T, Loc) | _] then
        Result = perr(diag(Loc, "E-UNSUPPORTED",
            "unsupported angle expression at " ++ describe(T)))
    else
        Result = perr(diag(loc(0, 0), "E-SYNTAX",
            "expected an angle, found end of input"))
    ).

:- pred combine_times(loc::in, aval::in, aval::in, float::in,
    list(ltok)::in, presult(float)::out) is det.

combine_times(Loc, A1, A2, Sign, Rest, Result) :-
    ( if A1 = num(X), A2 = pi_atom then
        Result = pok(Sign * X * pi_value, Rest)
    else if A1 = pi_atom, A2 = num(X) then
        Result = pok(Sign * pi_value * X, Rest)
    else if A1 = pi_atom, A2 = pi_atom then
        Result = perr(diag(Loc, "E-UNSUPPORTED",
            "pi may appear only once in an angle"))
    else
        Result = perr(diag(Loc, "E-UNSUPPORTED",
            "an angle product must contain pi"))
    ).

:- pred combine_divide(loc::in, aval::in, aval::in, float::in,
    list(ltok)::in, presult(float)::out) is det.

combine_divide(Loc, A1, A2, Sign, Rest, Result) :-
    ( if A1 = pi_atom, A2 = num(X), X \= 0.0 then
        Result = pok(Sign * pi_value / X, Rest)
    else if A1 = pi_atom, A2 = num(_) then
        Result = perr(diag(Loc, "E-UNSUPPORTED", "division of pi by zero"))
    else
        Result = perr(diag(Loc, "E-UNSUPPORTED",
            "an angle quotient must have the form pi / number"))
    ).

:- func pi_value = float.

pi_value = 3.141592653589793.

%---------------------------------------------------------------------------%
% Broadcast expansion

% Expand operands into single-qubit references. A whole-register operand
% expands to every index of the register, in order.
:- pred expand_qrefs(list(reg_decl)::in, loc::in, list(qref)::in,
    presult(list(qref))::out) is det.

expand_qrefs(_, _, [], pok([], [])).
expand_qrefs(Decls, Loc, [Q | Qs], Result) :-
    expand_qref(Decls, Loc, Q, HeadResult),
    (
        HeadResult = perr(D),
        Result = perr(D)
    ;
        HeadResult = pok(Hs, _),
        expand_qrefs(Decls, Loc, Qs, TailResult),
        (
            TailResult = perr(D),
            Result = perr(D)
        ;
            TailResult = pok(Ts, _),
            Result = pok(Hs ++ Ts, [])
        )
    ).

:- pred expand_qref(list(reg_decl)::in, loc::in, qref::in,
    presult(list(qref))::out) is det.

expand_qref(Decls, Loc, qref(Name, Index), Result) :-
    ( if Index \= -1 then
        Result = pok([qref(Name, Index)], [])
    else if find_register(Decls, Name, quantum, Size) then
        Result = pok(list.map(named_qref(Name), indices(Size)), [])
    else
        Result = perr(diag(Loc, "E-UNDECLARED",
            "undeclared quantum register '" ++ Name ++ "'"))
    ).

:- func named_qref(string, int) = qref.

named_qref(Name, K) = qref(Name, K).

% Expand a gate over its operands. Whole-register operands must agree in
% length (1 if there are none). Position k of the broadcast yields one
% unitary.
:- pred expand_gate(list(reg_decl)::in, loc::in, gate_kind::in,
    list(float)::in, list(qref)::in, presult(list(op))::out) is det.

expand_gate(Decls, Loc, Gate, Angles, Qrefs, Result) :-
    broadcast_length(Decls, Loc, Qrefs, LenResult),
    (
        LenResult = perr(D),
        Result = perr(D)
    ;
        LenResult = pok(Len, _),
        Result = pok(list.map(gate_at(Gate, Angles, Qrefs), indices(Len)), [])
    ).

:- func gate_at(gate_kind, list(float), list(qref), int) = op.

gate_at(Gate, Angles, Qrefs, K) =
    unitary(Gate, Angles, list.map(broadcast_at(K), Qrefs)).

% Expand a measurement. Both operands indexed: one measure. Both whole
% registers of equal size: pairwise.
:- pred expand_measure(list(reg_decl)::in, loc::in, bref::in, qref::in,
    presult(list(op))::out) is det.

expand_measure(Decls, Loc, bref(Dname, Dindex), qref(Qname, Qindex),
        Result) :-
    ( if Dindex = -1, Qindex = -1 then
        ( if find_register(Decls, Dname, classical, DSize),
                find_register(Decls, Qname, quantum, QSize),
                DSize = QSize then
            Result = pok(list.map(measure_at(Dname, Qname),
                indices(QSize)), [])
        else
            Result = perr(diag(Loc, "E-BROADCAST",
                "measure broadcast needs a classical and a quantum register"
                ++ " of equal size"))
        )
    else if Dindex \= -1, Qindex \= -1 then
        Result = pok([measure(qref(Qname, Qindex), bref(Dname, Dindex))], [])
    else
        Result = perr(diag(Loc, "E-BROADCAST",
            "measure operands must both be indexed or both be whole registers"))
    ).

:- func measure_at(string, string, int) = op.

measure_at(Dname, Qname, K) = measure(qref(Qname, K), bref(Dname, K)).

% Common length of the whole-register operands; 1 if there are none.
:- pred broadcast_length(list(reg_decl)::in, loc::in, list(qref)::in,
    presult(int)::out) is det.

broadcast_length(Decls, Loc, Qrefs, Result) :-
    collect_whole_sizes(Decls, Loc, Qrefs, SizesResult),
    (
        SizesResult = perr(D),
        Result = perr(D)
    ;
        SizesResult = pok(Sizes, _),
        ( if Sizes = [] then
            Result = pok(1, [])
        else if Sizes = [S | Ss], all_equal(S, Ss) then
            Result = pok(S, [])
        else
            Result = perr(diag(Loc, "E-BROADCAST",
                "operands of a broadcast have different register sizes"))
        )
    ).

% Sizes of the whole-register operands, in operand order.
:- pred collect_whole_sizes(list(reg_decl)::in, loc::in, list(qref)::in,
    presult(list(int))::out) is det.

collect_whole_sizes(_, _, [], pok([], [])).
collect_whole_sizes(Decls, Loc, [qref(Name, Index) | Qs], Result) :-
    collect_whole_sizes(Decls, Loc, Qs, TailResult),
    (
        TailResult = perr(D),
        Result = perr(D)
    ;
        TailResult = pok(Sizes, _),
        ( if Index \= -1 then
            Result = pok(Sizes, [])
        else if find_register(Decls, Name, quantum, Size) then
            Result = pok([Size | Sizes], [])
        else
            Result = perr(diag(Loc, "E-UNDECLARED",
                "undeclared quantum register '" ++ Name ++ "'"))
        )
    ).

:- pred all_equal(int::in, list(int)::in) is semidet.

all_equal(_, []).
all_equal(S, [T | Ts]) :-
    S = T,
    all_equal(S, Ts).

:- func broadcast_at(int, qref) = qref.

broadcast_at(K, qref(N, I)) = qref(N, ( if I = -1 then K else I )).

%---------------------------------------------------------------------------%
% Helpers

% Look up a register declared so far.
:- pred find_register(list(reg_decl)::in, string::in, reg_kind::in,
    int::out) is semidet.

find_register(Decls, Name, Kind, Size) :-
    list.find_first_match(is_register(Name, Kind), Decls,
        reg_decl(_, Size, _, _)).

:- pred is_register(string::in, reg_kind::in, reg_decl::in) is semidet.

is_register(Name, Kind, reg_decl(Name, _, Kind, _)).

% Consume the given symbol, or report what was found instead.
:- pred expect_sym(string::in, list(ltok)::in, presult(unit)::out) is det.

expect_sym(Sym, Toks, Result) :-
    ( if Toks = [ltok(tok_sym(S), _) | Rest], S = Sym then
        Result = pok(unit, Rest)
    else if Toks = [ltok(T, Loc) | _] then
        Result = perr(diag(Loc, "E-SYNTAX",
            "expected '" ++ Sym ++ "', found " ++ describe(T)))
    else
        Result = perr(diag(loc(0, 0), "E-SYNTAX",
            "expected '" ++ Sym ++ "', found end of input"))
    ).

% The integers 0 .. N-1.
:- func indices(int) = list(int).

indices(N) = ( if N =< 0 then [] else indices_from(0, N) ).

:- func indices_from(int, int) = list(int).

indices_from(K, N) = ( if K >= N then [] else [K | indices_from(K + 1, N)] ).

:- func describe(token) = string.

describe(tok_ident(S)) = "'" ++ S ++ "'".
describe(tok_int(I)) = int_to_string(I).
describe(tok_real(F)) = string.format("%g", [f(F)]).
describe(tok_string(S)) = "\"" ++ S ++ "\"".
describe(tok_sym(S)) = "'" ++ S ++ "'".
describe(tok_eof) = "end of input".

%---------------------------------------------------------------------------%
:- end_module parser.
%---------------------------------------------------------------------------%
