% SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
% Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
% Authored by Ahmad Ali Parr.
% Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

%---------------------------------------------------------------------------%
% diagnostic.m
%
% Compiler diagnostics: a located error or warning with a stable code.
%
% Purpose:    Carry every reported problem with its source location, a code
%             that tests can match on, and a human-readable message.
% Codes:      E-LEX         lexical error
%             E-SYNTAX      grammar violation
%             E-UNSUPPORTED construct outside the supported subset
%             E-UNDECLARED  register used before declaration
%             E-DUPLICATE   register declared twice
%             E-SIZE        register size below 1
%             E-RANGE       index outside register bounds
%             E-ARITY       wrong number of qubit operands or angles
%             E-OPERANDS    two-qubit gate with repeated operand
%             E-BROADCAST   mismatched register sizes in a broadcast
%             W-BIT-REWRITE classical bit assigned more than once
% Failures:   None. Pure formatting.
%
%---------------------------------------------------------------------------%

:- module diagnostic.
:- interface.

:- import_module circuit.

:- type diag
    --->    diag(diag_loc :: loc, diag_code :: string, diag_msg :: string).

% Render as "FILE:LINE:COL: error[CODE]: MESSAGE", or "warning" for W- codes.
:- func format_diag(string, diag) = string.

% True if the diagnostic is an error (not a warning).
:- pred is_error(diag::in) is semidet.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module string.

format_diag(File, diag(loc(Line, Col), Code, Msg)) =
    File ++ ":" ++ int_to_string(Line) ++ ":" ++ int_to_string(Col) ++ ": "
        ++ severity(Code) ++ "[" ++ Code ++ "]: " ++ Msg.

:- func severity(string) = string.

severity(Code) = ( if string.prefix(Code, "W-") then "warning" else "error" ).

is_error(D) :-
    not string.prefix(D^diag_code, "W-").

%---------------------------------------------------------------------------%
:- end_module diagnostic.
%---------------------------------------------------------------------------%
