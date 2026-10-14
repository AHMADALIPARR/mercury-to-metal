%---------------------------------------------------------------------------%
% optimize.m
%
% Semantics-preserving peephole optimization of a validated circuit.
%
% Purpose:    Remove identity operations and combine adjacent gates, without
%             changing the unitary the circuit denotes.
% Inputs:     A circuit that passed validate.m.
% Outputs:    A circuit with the same declarations (moved to the front, in
%             their original order, which keeps every use after its
%             declaration) and an optimized operation list.
% Rewrites (applied only to the two most recent kept operations):
%   R1  id                              -> removed
%   R2  rx(0), ry(0), rz(0), cp(0)      -> removed
%   R3  g g on the same operands, g in {x y z h cx cz swap}   -> removed
%   R4  s sdg, sdg s, t tdg, tdg t on the same qubit          -> removed
%   R5  rx(a) rx(b), ry(a) ry(b), rz(a) rz(b), cp(a) cp(b)
%       on the same operands                                  -> one gate
%       with angle a + b
% "Same operands" means identical ordered operands, or the reversed pair for
% gates that are symmetric in their operands (cz, swap, cp).
% Measure, reset and barrier are never rewritten and never crossed: they are
% kept on the stack, so nothing combines across them.
% Rules are applied in one forward pass with a stack. Each kept operation is
% compared only with the most recently kept one, which is the immediately
% preceding operation in the optimized sequence; the pass therefore never
% reorders operations. Operations are not commuted, so some reducible pairs
% separated by disjoint gates are left in place.
% Failures:   None.
%
%---------------------------------------------------------------------------%

:- module optimize.
:- interface.

:- import_module circuit.

:- func optimize(circuit) = circuit.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module float.
:- import_module list.

optimize(circuit(Items)) = circuit(Decls ++ list.map(op_item, Ops)) :-
    split_items(Items, Decls, Stmts),
    push_all(Stmts, [], Stack),
    Ops = list.reverse(Stack).

:- func op_item(stmt) = item.

op_item(S) = op(S).

% Separate declarations (kept in order) from statements (kept in order).
:- pred split_items(list(item)::in, list(item)::out, list(stmt)::out) is det.

split_items([], [], []).
split_items([Item | Items], Decls, Stmts) :-
    split_items(Items, Decls0, Stmts0),
    ( if Item = decl(_) then
        Decls = [Item | Decls0],
        Stmts = Stmts0
    else if Item = op(S) then
        Decls = Decls0,
        Stmts = [S | Stmts0]
    else
        Decls = Decls0,
        Stmts = Stmts0
    ).

% Push each statement onto the stack of kept statements, most recent first.
:- pred push_all(list(stmt)::in, list(stmt)::in, list(stmt)::out) is det.

push_all([], Stack, Stack).
push_all([S | Ss], Stack0, Stack) :-
    push_stmt(S, Stack0, Stack1),
    push_all(Ss, Stack1, Stack).

:- pred push_stmt(stmt::in, list(stmt)::in, list(stmt)::out) is det.

push_stmt(S, Stack0, Stack) :-
    ( if is_identity_op(S ^ stmt_op) then
        Stack = Stack0
    else if Stack0 = [Top | Rest], C = combine(Top ^ stmt_op, S ^ stmt_op),
            C \= none then
        apply_combined(C, Top, Rest, Stack)
    else
        Stack = [S | Stack0]
    ).

:- pred apply_combined(combined::in, stmt::in, list(stmt)::in,
    list(stmt)::out) is det.

apply_combined(cancel, _, Rest, Rest).
apply_combined(none, Top, Rest, [Top | Rest]).
apply_combined(merged(Op), Top, Rest, Stack) :-
    ( if is_identity_op(Op) then
        Stack = Rest
    else
        Stack = [stmt(Top ^ stmt_loc, Op) | Rest]
    ).

:- type combined
    --->    cancel
    ;       merged(op)
    ;       none.

% True for operations that act as the identity.
:- pred is_identity_op(op::in) is semidet.

is_identity_op(unitary(gk_id, [], _)).
is_identity_op(unitary(Gate, [A], _)) :-
    list.member(Gate, [gk_rx, gk_ry, gk_rz, gk_cp]),
    A = 0.0.

% combine(First, Second): rewrite of the sequence First; Second.
:- func combine(op, op) = combined.

combine(First, Second) = C :-
    ( if First = unitary(G, [], Qs), Second = unitary(G2, [], Qs2),
            G = G2, is_self_inverse(G), same_operands(G, Qs, Qs2) then
        C = cancel
    else if First = unitary(G, [], Qs), Second = unitary(G2, [], Qs2),
            inverse_pair(G, G2), Qs = Qs2 then
        C = cancel
    else if First = unitary(G, [A], Qs), Second = unitary(G2, [B], Qs2),
            G = G2, is_additive(G), same_operands(G, Qs, Qs2) then
        C = merged(unitary(G, [A + B], Qs))
    else
        C = none
    ).

% Rotations whose angles add.
:- pred is_additive(gate_kind::in) is semidet.

is_additive(gk_rx).
is_additive(gk_ry).
is_additive(gk_rz).
is_additive(gk_cp).

:- pred inverse_pair(gate_kind::in, gate_kind::in) is semidet.

inverse_pair(gk_s, gk_sdg).
inverse_pair(gk_sdg, gk_s).
inverse_pair(gk_t, gk_tdg).
inverse_pair(gk_tdg, gk_t).

:- pred same_operands(gate_kind::in, list(qref)::in, list(qref)::in)
    is semidet.

same_operands(_, Qs, Qs).
same_operands(G, [A, B], [B, A]) :-
    is_symmetric(G),
    A \= B.

%---------------------------------------------------------------------------%
:- end_module optimize.
%---------------------------------------------------------------------------%
