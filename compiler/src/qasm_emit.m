%---------------------------------------------------------------------------%
% qasm_emit.m
%
% OpenQASM 3 emitter for the frozen subset in
% specifications/interchange/QASM_SUBSET.md.
%
% Purpose:    Lower a validated circuit to OpenQASM 3 text.
% Inputs:     A circuit that passed validate.m. Behavior on invalid circuits
%             is unspecified; callers must validate first.
% Outputs:    Program text: header, declarations in source order, then one
%             line per operation. Angles render with %.17g, which round-trips
%             IEEE-754 binary64 exactly. Output is byte-deterministic: no
%             timestamps, no unordered iteration, LF endings, one trailing
%             newline.
% Failures:   None.
%
%---------------------------------------------------------------------------%

:- module qasm_emit.
:- interface.

:- import_module circuit.
:- import_module string.

:- func emit_qasm(circuit) = string.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module float.
:- import_module int.
:- import_module list.

emit_qasm(circuit(Items)) =
    "OPENQASM 3.0;\n" ++
    "include \"stdgates.inc\";\n" ++
    string.append_list(list.map(emit_item, Items)).

:- func emit_item(item) = string.

emit_item(decl(reg_decl(Name, Size, Kind, _))) =
    ( if Kind = quantum then "qubit" else "bit" ) ++
    "[" ++ int_to_string(Size) ++ "] " ++ Name ++ ";\n".
emit_item(op(stmt(_, Op))) = emit_op(Op) ++ ";\n".

:- func emit_op(op) = string.

emit_op(unitary(Gate, Angles, Qs)) =
    gate_name(Gate) ++ angle_list(Angles) ++ " " ++ qref_list(Qs).
emit_op(measure(Q, B)) =
    bref_string(B) ++ " = measure " ++ qref_string(Q).
emit_op(reset(Q)) =
    "reset " ++ qref_string(Q).
emit_op(barrier(Qs)) =
    "barrier " ++ qref_list(Qs).

:- func angle_list(list(float)) = string.

angle_list([]) = "".
angle_list([A | As]) = "(" ++ string.join_list(", ",
    list.map(angle_text, [A | As])) ++ ")".

:- func angle_text(float) = string.

angle_text(A) = string.format("%.17g", [f(A)]).

:- func qref_list(list(qref)) = string.

qref_list(Qs) = string.join_list(", ", list.map(qref_string, Qs)).

%---------------------------------------------------------------------------%
:- end_module qasm_emit.
%---------------------------------------------------------------------------%
