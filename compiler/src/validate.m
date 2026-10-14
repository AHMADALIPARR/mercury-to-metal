%---------------------------------------------------------------------------%
% validate.m
%
% Semantic validation of a circuit. Reports every violation, not only the
% first, so one run gives a complete picture.
%
% Purpose:    Enforce the invariants of specifications/compiler/CIRCUIT_IR.md.
% Inputs:     A circuit as produced by parser.m (declarations and operations in
%             source order).
% Outputs:    A list of diagnostics; empty means the circuit is valid. Warnings
%             do not make a circuit invalid.
% Invariants checked:
%   1. Register sizes are at least 1                                E-SIZE
%   2. Register names are unique                                    E-DUPLICATE
%   3. Quantum operands name a declared quantum register            E-UNDECLARED
%   4. Classical operands name a declared classical register        E-UNDECLARED
%   5. Indices lie in [0, size)                                     E-RANGE
%   6. Unitary arity and parameter count match the gate             E-ARITY
%   7. Two-qubit unitary operands are distinct                      E-OPERANDS
%   8. A barrier has at least one operand                           E-ARITY
%   9. A classical bit assigned more than once is reported          W-BIT-REWRITE
% Semantics of checks 3-5 depend on declarations that appear earlier in the
% source, so a use before its declaration is reported as undeclared.
% Failures:   None; validation is total.
%
%---------------------------------------------------------------------------%

:- module validate.
:- interface.

:- import_module circuit.
:- import_module diagnostic.
:- import_module list.

:- pred validate(circuit::in, list(diag)::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module string.

:- pred validate_items(list(item)::in, list(reg_decl)::in, list(bref)::in,
    list(diag)::in, list(diag)::out) is det.

validate(circuit(Items), Diags) :-
    validate_items(Items, [], [], [], RevDiags),
    Diags = list.reverse(RevDiags).

validate_items([], _, _, Acc, Acc).
validate_items([Item | Items], Decls, Written, Acc, Diags) :-
    ( if Item = decl(Decl) then
        check_decl(Decl, Decls, Acc, Acc1),
        validate_items(Items, Decls ++ [Decl], Written, Acc1, Diags)
    else if Item = op(stmt(Loc, Op)) then
        check_op(Loc, Op, Decls, Written, Acc, Acc1, Written1),
        validate_items(Items, Decls, Written1, Acc1, Diags)
    else
        validate_items(Items, Decls, Written, Acc, Diags)
    ).

:- pred check_decl(reg_decl::in, list(reg_decl)::in, list(diag)::in,
    list(diag)::out) is det.

check_decl(reg_decl(Name, Size, _, Loc), Earlier, Acc, Diags) :-
    Diags1 = ( if Size < 1 then
        [diag(Loc, "E-SIZE", "register '" ++ Name ++ "' must have size >= 1")
            | Acc]
    else
        Acc
    ),
    Diags = ( if list.any_true(same_name(Name), Earlier) then
        [diag(Loc, "E-DUPLICATE", "register '" ++ Name
            ++ "' is already declared") | Diags1]
    else
        Diags1
    ).

:- pred same_name(string::in, reg_decl::in) is semidet.

same_name(Name, reg_decl(Name, _, _, _)).

% check_op(Loc, Op, Decls, Written, Acc0, Acc, Written1)
:- pred check_op(loc::in, op::in, list(reg_decl)::in, list(bref)::in,
    list(diag)::in, list(diag)::out, list(bref)::out) is det.

check_op(Loc, unitary(Gate, Angles, Qs), Decls, Written, Acc, Diags,
        Written) :-
    arity_diags(Loc, Gate, Angles, Qs, Acc, Acc1),
    list.foldl(check_qref(Loc, Decls), Qs, Acc1, Acc2),
    operand_diags(Loc, Gate, Qs, Acc2, Diags).
check_op(Loc, measure(Q, B), Decls, Written, Acc, Diags, Written1) :-
    check_qref(Loc, Decls, Q, Acc, Acc1),
    check_bref(Loc, Decls, B, Acc1, Acc2),
    ( if list.member(B, Written) then
        Written1 = Written,
        Diags = [diag(Loc, "W-BIT-REWRITE", "classical bit '"
            ++ bref_string(B) ++ "' is assigned more than once") | Acc2]
    else
        Written1 = [B | Written],
        Diags = Acc2
    ).
check_op(Loc, reset(Q), Decls, Written, Acc, Diags, Written) :-
    check_qref(Loc, Decls, Q, Acc, Diags).
check_op(Loc, barrier(Qs), Decls, Written, Acc, Diags, Written) :-
    ( if Qs = [] then
        Acc1 = [diag(Loc, "E-ARITY", "barrier needs at least one operand")
            | Acc]
    else
        Acc1 = Acc
    ),
    list.foldl(check_qref(Loc, Decls), Qs, Acc1, Diags).

:- pred arity_diags(loc::in, gate_kind::in, list(float)::in, list(qref)::in,
    list(diag)::in, list(diag)::out) is det.

arity_diags(Loc, Gate, Angles, Qs, Acc, Diags) :-
    Acc1 = ( if list.length(Qs) \= gate_arity(Gate) then
        [diag(Loc, "E-ARITY", "gate '" ++ gate_name(Gate) ++ "' acts on "
            ++ int_to_string(gate_arity(Gate)) ++ " qubit(s), given "
            ++ int_to_string(list.length(Qs))) | Acc]
    else
        Acc
    ),
    Diags = ( if list.length(Angles) \= gate_num_params(Gate) then
        [diag(Loc, "E-ARITY", "gate '" ++ gate_name(Gate) ++ "' takes "
            ++ int_to_string(gate_num_params(Gate)) ++ " angle(s), given "
            ++ int_to_string(list.length(Angles))) | Acc1]
    else
        Acc1
    ).

:- pred operand_diags(loc::in, gate_kind::in, list(qref)::in,
    list(diag)::in, list(diag)::out) is det.

operand_diags(Loc, Gate, Qs, Acc, Diags) :-
    ( if Qs = [A, B], gate_arity(Gate) = 2, A = B then
        Diags = [diag(Loc, "E-OPERANDS", "two-qubit gate '"
            ++ gate_name(Gate) ++ "' repeats operand " ++ qref_string(A))
            | Acc]
    else
        Diags = Acc
    ).

:- pred check_qref(loc::in, list(reg_decl)::in, qref::in,
    list(diag)::in, list(diag)::out) is det.

check_qref(Loc, Decls, qref(Name, Index), Acc, Diags) :-
    ( if find_size(Decls, Name, quantum, Size) then
        ( if Index >= 0, Index < Size then
            Diags = Acc
        else
            Diags = [diag(Loc, "E-RANGE", "qubit index " ++ qref_string(
                qref(Name, Index)) ++ " is outside 0.." ++ int_to_string(
                Size - 1)) | Acc]
        )
    else
        Diags = [diag(Loc, "E-UNDECLARED", "undeclared quantum register '"
            ++ Name ++ "'") | Acc]
    ).

:- pred check_bref(loc::in, list(reg_decl)::in, bref::in,
    list(diag)::in, list(diag)::out) is det.

check_bref(Loc, Decls, bref(Name, Index), Acc, Diags) :-
    ( if find_size(Decls, Name, classical, Size) then
        ( if Index >= 0, Index < Size then
            Diags = Acc
        else
            Diags = [diag(Loc, "E-RANGE", "bit index " ++ bref_string(
                bref(Name, Index)) ++ " is outside 0.." ++ int_to_string(
                Size - 1)) | Acc]
        )
    else
        Diags = [diag(Loc, "E-UNDECLARED", "undeclared classical register '"
            ++ Name ++ "'") | Acc]
    ).

:- pred find_size(list(reg_decl)::in, string::in, reg_kind::in, int::out)
    is semidet.

find_size(Decls, Name, Kind, Size) :-
    list.find_first_match(is_reg(Name, Kind), Decls,
        reg_decl(_, Size, _, _)).

:- pred is_reg(string::in, reg_kind::in, reg_decl::in) is semidet.

is_reg(Name, Kind, reg_decl(Name, _, Kind, _)).

%---------------------------------------------------------------------------%
:- end_module validate.
%---------------------------------------------------------------------------%
