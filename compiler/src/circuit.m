%---------------------------------------------------------------------------%
% circuit.m
%
% Typed circuit IR for the Mercury-to-Metal compiler.
%
% Purpose:    Define the internal representation of a quantum circuit: gate
%             kinds, register declarations, qubit and bit references, and
%             operations. Unitary gates and nonunitary operations (measure,
%             reset) are distinct constructors.
% Inputs:     Constructed by parser.m and by the optimizer.
% Outputs:    Consumed by validate.m, optimize.m, statevector.m, qasm_emit.m.
% Invariants: See specifications/compiler/CIRCUIT_IR.md. Arity and parameter
%             count of unitary/2 are checked by validate.m, not here, so that
%             the parser can report source locations.
% Failures:   None. This module is total.
%
%---------------------------------------------------------------------------%

:- module circuit.
:- interface.

:- import_module list.
:- import_module string.

%---------------------------------------------------------------------------%

:- type loc
    --->    loc(line :: int, col :: int).

:- type gate_kind
    --->    gk_id
    ;       gk_x
    ;       gk_y
    ;       gk_z
    ;       gk_h
    ;       gk_s
    ;       gk_sdg
    ;       gk_t
    ;       gk_tdg
    ;       gk_rx
    ;       gk_ry
    ;       gk_rz
    ;       gk_cx
    ;       gk_cz
    ;       gk_swap
    ;       gk_cp.

:- type reg_kind
    --->    quantum
    ;       classical.

% A register declaration. Size is the number of qubits or bits.
:- type reg_decl
    --->    reg_decl(reg_name :: string, reg_size :: int,
                reg_kind :: reg_kind, reg_loc :: loc).

% A reference to one qubit of a quantum register. index = -1 denotes the
% whole register; the parser expands whole-register references (broadcast)
% before any operation reaches validation or the optimizer.
:- type qref
    --->    qref(qreg :: string, qindex :: int).

:- type bref
    --->    bref(breg :: string, bindex :: int).

:- type op
    --->    unitary(gate_kind, list(float), list(qref))
    ;       measure(qref, bref)
    ;       reset(qref)
    ;       barrier(list(qref)).

:- type stmt
    --->    stmt(stmt_loc :: loc, stmt_op :: op).

:- type item
    --->    decl(reg_decl)
    ;       op(stmt).

:- type circuit
    --->    circuit(circuit_items :: list(item)).

%---------------------------------------------------------------------------%

% The surface name of each gate, as written in source and in OpenQASM 3.
:- func gate_name(gate_kind) = string.

% Look up a gate by its surface name. Fails on unknown names.
:- pred gate_from_name(string::in, gate_kind::out) is semidet.

% Number of qubit operands the gate acts on.
:- func gate_arity(gate_kind) = int.

% Number of angle parameters the gate takes.
:- func gate_num_params(gate_kind) = int.

% True if applying the gate twice on the same operands gives the identity.
:- pred is_self_inverse(gate_kind::in) is semidet.

% True if the gate's operand list is invariant under reversal.
:- pred is_symmetric(gate_kind::in) is semidet.

% Render a qubit reference as name[index].
:- func qref_string(qref) = string.

% Render a bit reference as name[index].
:- func bref_string(bref) = string.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module require.

gate_name(gk_id) = "id".
gate_name(gk_x) = "x".
gate_name(gk_y) = "y".
gate_name(gk_z) = "z".
gate_name(gk_h) = "h".
gate_name(gk_s) = "s".
gate_name(gk_sdg) = "sdg".
gate_name(gk_t) = "t".
gate_name(gk_tdg) = "tdg".
gate_name(gk_rx) = "rx".
gate_name(gk_ry) = "ry".
gate_name(gk_rz) = "rz".
gate_name(gk_cx) = "cx".
gate_name(gk_cz) = "cz".
gate_name(gk_swap) = "swap".
gate_name(gk_cp) = "cp".

gate_from_name(Name, Gate) :-
    list.find_first_match(
        (pred(G::in) is semidet :- gate_name(G) = Name),
        all_gates, Gate).

:- func all_gates = list(gate_kind).

all_gates = [gk_id, gk_x, gk_y, gk_z, gk_h, gk_s, gk_sdg, gk_t, gk_tdg,
    gk_rx, gk_ry, gk_rz, gk_cx, gk_cz, gk_swap, gk_cp].

gate_arity(Gate) = ( if list.member(Gate, [gk_cx, gk_cz, gk_swap, gk_cp])
    then 2 else 1 ).

gate_num_params(Gate) = ( if list.member(Gate, [gk_rx, gk_ry, gk_rz, gk_cp])
    then 1 else 0 ).

is_self_inverse(gk_id).
is_self_inverse(gk_x).
is_self_inverse(gk_y).
is_self_inverse(gk_z).
is_self_inverse(gk_h).
is_self_inverse(gk_cx).
is_self_inverse(gk_cz).
is_self_inverse(gk_swap).

is_symmetric(gk_cz).
is_symmetric(gk_swap).
is_symmetric(gk_cp).

qref_string(qref(Reg, Index)) = Reg ++ "[" ++ int_to_string(Index) ++ "]".

bref_string(bref(Reg, Index)) = Reg ++ "[" ++ int_to_string(Index) ++ "]".

%---------------------------------------------------------------------------%
:- end_module circuit.
%---------------------------------------------------------------------------%
