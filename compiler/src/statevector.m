% SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
% Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
% Authored by Ahmad Ali Parr.
% Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

%---------------------------------------------------------------------------%
% statevector.m
%
% Independent statevector evaluator for small unitary circuits. It is the
% reference against which optimized and emitted circuits are compared.
%
% Purpose:    Compute the final statevector of a unitary circuit.
% Inputs:     A circuit that passed validate.m, containing only unitary
%             operations and barriers.
% Outputs:    sv_ok(amplitudes), with amplitudes in computational-basis order;
%             or sv_err(reason) for nonunitary operations or too many qubits.
% Conventions:
%   - Quantum registers are concatenated in declaration order. Global qubit g
%     is bit g of the basis index (little-endian).
%   - Gate matrices are the standard ones: rx(t) = exp(-i t X / 2),
%     ry(t) = exp(-i t Y / 2), rz(t) = exp(-i t Z / 2), cp(t) = diag(1,1,1,e^{it}).
%   - The state is not normalized after measurement because measurement is
%     rejected; unitary evolution preserves the norm, which the tests check.
% Limits:     At most max_qubits qubits (2^20 amplitudes, 16 MiB).
% Failures:   Nonunitary operations, and register totals above max_qubits.
%
%---------------------------------------------------------------------------%

:- module statevector.
:- interface.

:- import_module circuit.
:- import_module list.

:- type cpx
    --->    cpx(re :: float, im :: float).

:- type sv_result
    --->    sv_ok(list(cpx))
    ;       sv_err(string).

:- func max_qubits = int.

:- pred statevector(circuit::in, sv_result::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module array.
:- import_module float.
:- import_module int.
:- import_module math.
:- import_module require.
:- import_module string.

max_qubits = 20.

:- type mat
    --->    mat(cpx, cpx, cpx, cpx).     % [[a, b], [c, d]]

% A unitary action on the basis, with qubit bits as powers of two.
:- type action
    --->    single(mat, int)             % 1-qubit matrix on bit B
    ;       controlled_x(int, int)       % CX: control bit C, target bit T
    ;       swap_bits(int, int)          % SWAP of bits A, B
    ;       diagonal(cpx, int, int).     % phase P when bits A and B are set

statevector(circuit(Items), Result) :-
    collect_layout(Items, 0, Layout, Total),
    ( if Total > max_qubits then
        Result = sv_err("statevector limited to " ++
            int_to_string(max_qubits) ++ " qubits")
    else if has_nonunitary(Items) then
        Result = sv_err("statevector evaluation requires a unitary circuit")
    else
        Dim = pow2(Total),
        array.init(Dim, cpx(0.0, 0.0), Zero),
        array.set(0, cpx(1.0, 0.0), Zero, Start),
        run_items(Items, Layout, Start, Final),
        Result = sv_ok(array.to_list(Final))
    ).

% Global offset of each quantum register, in declaration order. Returns the
% total number of quantum qubits.
:- type layout == list({string, int}).

:- pred collect_layout(list(item)::in, int::in, layout::out, int::out)
    is det.

collect_layout([], Offset, [], Offset).
collect_layout([Item | Items], Offset0, Layout, Total) :-
    ( if Item = decl(reg_decl(Name, Size, quantum, _)) then
        collect_layout(Items, Offset0 + Size, Rest, Total),
        Layout = [{Name, Offset0} | Rest]
    else
        collect_layout(Items, Offset0, Layout, Total)
    ).

:- func pow2(int) = int.

pow2(K) = ( if K =< 0 then 1 else 2 * pow2(K - 1) ).

:- pred has_nonunitary(list(item)::in) is semidet.

has_nonunitary([Item | Items]) :-
    ( if Item = op(stmt(_, measure(_, _))) then
        true
    else if Item = op(stmt(_, reset(_))) then
        true
    else
        has_nonunitary(Items)
    ).

:- pred run_items(list(item)::in, layout::in, array(cpx)::array_di,
    array(cpx)::array_uo) is det.

run_items([], _, S, S).
run_items([Item | Items], Layout, S0, S) :-
    ( if Item = op(stmt(_, unitary(Gate, Angles, Qs))) then
        Actions = list.map(qubit_index(Layout), Qs),
        apply_gate(Gate, Angles, Actions, S0, S1)
    else
        S1 = S0
    ),
    run_items(Items, Layout, S1, S).

% Global index of a qubit. Validation guarantees the register exists.
:- func qubit_index(layout, qref) = int.

qubit_index(Layout, qref(Name, Index)) = Offset + Index :-
    register_offset(Layout, Name, Offset).

:- pred register_offset(layout::in, string::in, int::out) is det.

register_offset([], Name, _) :-
    error("statevector: unknown register " ++ Name).
register_offset([{N, Offset0} | Rest], Name, Offset) :-
    ( if N = Name then
        Offset = Offset0
    else
        register_offset(Rest, Name, Offset)
    ).

:- pred apply_gate(gate_kind::in, list(float)::in, list(int)::in,
    array(cpx)::array_di, array(cpx)::array_uo) is det.

apply_gate(Gate, Angles, Actions, S0, S) :-
    ( if Actions = [Q] then
        ( if Angles = [T] then
            single_qubit_gate(Gate, T, Q, Action)
        else
            single_qubit_gate(Gate, 0.0, Q, Action)
        ),
        apply_action(Action, S0, S)
    else if Actions = [A, B] then
        ( if Angles = [T] then
            two_qubit_gate(Gate, T, A, B, Action)
        else
            two_qubit_gate(Gate, 0.0, A, B, Action)
        ),
        apply_action(Action, S0, S)
    else
        error("statevector: unexpected operand count")
    ).

:- pred single_qubit_gate(gate_kind::in, float::in, int::in, action::out)
    is det.

single_qubit_gate(Gate, T, Q, single(M, pow2(Q))) :-
    gate_matrix(Gate, T, M).

:- pred two_qubit_gate(gate_kind::in, float::in, int::in, int::in,
    action::out) is det.

two_qubit_gate(gk_cx, _, C, T, controlled_x(pow2(C),
    pow2(T))).
two_qubit_gate(gk_cz, _, A, B, diagonal(cpx(-1.0, 0.0), pow2(A),
    pow2(B))).
two_qubit_gate(gk_swap, _, A, B, swap_bits(pow2(A),
    pow2(B))).
two_qubit_gate(gk_cp, T, A, B, diagonal(exp_i(T), pow2(A),
    pow2(B))).
two_qubit_gate(_, _, _, _, _) :-
    error("statevector: two operands for a one-qubit gate").

:- pred gate_matrix(gate_kind::in, float::in, mat::out) is det.

gate_matrix(gk_id, _, mat(one, zero, zero, one)).
gate_matrix(gk_x, _, mat(zero, one, one, zero)).
gate_matrix(gk_y, _, mat(zero, cpx(0.0, -1.0), cpx(0.0, 1.0), zero)).
gate_matrix(gk_z, _, mat(one, zero, zero, cpx(-1.0, 0.0))).
gate_matrix(gk_h, _, mat(cpx(R, 0.0), cpx(R, 0.0), cpx(R, 0.0),
    cpx(-R, 0.0))) :-
    R = 1.0 / sqrt(2.0).
gate_matrix(gk_s, _, mat(one, zero, zero, cpx(0.0, 1.0))).
gate_matrix(gk_sdg, _, mat(one, zero, zero, cpx(0.0, -1.0))).
gate_matrix(gk_t, _, mat(one, zero, zero, exp_i(pi_value / 4.0))).
gate_matrix(gk_tdg, _, mat(one, zero, zero, exp_i(-pi_value / 4.0))).
gate_matrix(gk_rx, T, mat(cpx(cos(T / 2.0), 0.0), cpx(0.0, -sin(T / 2.0)),
    cpx(0.0, -sin(T / 2.0)), cpx(cos(T / 2.0), 0.0))).
gate_matrix(gk_ry, T, mat(cpx(cos(T / 2.0), 0.0), cpx(-sin(T / 2.0), 0.0),
    cpx(sin(T / 2.0), 0.0), cpx(cos(T / 2.0), 0.0))).
gate_matrix(gk_rz, T, mat(exp_i(-T / 2.0), zero, zero, exp_i(T / 2.0))).
gate_matrix(gk_cx, _, mat(zero, one, one, zero)).
gate_matrix(gk_cz, _, mat(one, zero, zero, cpx(-1.0, 0.0))).
gate_matrix(gk_swap, _, mat(zero, one, one, zero)).
gate_matrix(gk_cp, _, mat(one, zero, zero, one)).

:- func pi_value = float.

pi_value = 3.141592653589793.

:- func one = cpx.
:- func zero = cpx.

one = cpx(1.0, 0.0).
zero = cpx(0.0, 0.0).

:- func exp_i(float) = cpx.

exp_i(T) = cpx(cos(T), sin(T)).

:- pred apply_action(action::in, array(cpx)::array_di,
    array(cpx)::array_uo) is det.

apply_action(Action, S0, S) :-
    Dim = array.size(S0),
    sweep(Action, 0, Dim, S0, S).

% Visit every basis index once. A pair action updates index I together with
% its partner J; visiting the partner is skipped by the bit condition.
:- pred sweep(action::in, int::in, int::in, array(cpx)::array_di,
    array(cpx)::array_uo) is det.

sweep(Action, I, Dim, S0, S) :-
    ( if I >= Dim then
        S = S0
    else
        visit(Action, I, S0, S1),
        sweep(Action, I + 1, Dim, S1, S)
    ).

:- pred visit(action::in, int::in, array(cpx)::array_di,
    array(cpx)::array_uo) is det.

visit(Action, I, S0, S) :-
    ( if pair_partner(Action, I, J, M) then
        pair_update(M, I, J, S0, S)
    else if phase_at(Action, I, P) then
        array.lookup(S0, I) = X,
        array.set(I, cmul(P, X), S0, S)
    else
        S = S0
    ).

% Pair actions: the mapping on (I, J) and the 2x2 matrix to apply. Each
% pair is produced once, from its member with the action's bit unset.
:- pred pair_partner(action::in, int::in, int::out, mat::out) is semidet.

pair_partner(single(M, B), I, I + B, M) :-
    not bit_set(I, B).
pair_partner(controlled_x(C, T), I, I + T, mat(zero, one, one, zero)) :-
    bit_set(I, C),
    not bit_set(I, T).
pair_partner(swap_bits(A, B), I, J, mat(zero, one, one, zero)) :-
    bit_set(I, A),
    not bit_set(I, B),
    J = I - A + B.

% Diagonal actions: a phase applied to indices where all relevant bits are set.
:- pred phase_at(action::in, int::in, cpx::out) is semidet.

phase_at(diagonal(P, A, B), I, P) :-
    bit_set(I, A),
    bit_set(I, B).

:- pred bit_set(int::in, int::in) is semidet.

bit_set(I, B) :-
    (I // B) mod 2 = 1.

:- pred pair_update(mat::in, int::in, int::in, array(cpx)::array_di,
    array(cpx)::array_uo) is det.

pair_update(mat(A, B, C, D), I, J, S0, S) :-
    array.lookup(S0, I) = X,
    array.lookup(S0, J) = Y,
    array.set(I, cadd(cmul(A, X), cmul(B, Y)), S0, S1),
    array.set(J, cadd(cmul(C, X), cmul(D, Y)), S1, S).

:- func cmul(cpx, cpx) = cpx.

cmul(cpx(A, B), cpx(C, D)) = cpx(A * C - B * D, A * D + B * C).

:- func cadd(cpx, cpx) = cpx.

cadd(cpx(A, B), cpx(C, D)) = cpx(A + C, B + D).

%---------------------------------------------------------------------------%
:- end_module statevector.
%---------------------------------------------------------------------------%
