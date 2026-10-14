# Circuit IR (v0)

The IR is the single internal representation. OpenQASM 3 is an output format only.

## Types

```
register   := reg(name, size, kind)          kind ∈ {quantum, classical}
qubit_ref  := qref(reg_index, offset)        offset ∈ [0, size)
bit_ref    := bref(reg_index, offset)
angle      := float64                      // radians, finite; `pi` forms are evaluated at parse
op         := unitary(gate_kind, angle*, qubit_ref+)
           | measure(qubit_ref, bit_ref)  // nonunitary
           | reset(qubit_ref)             // nonunitary
           | barrier(qubit_ref+)          // scheduling fence, no unitary effect
gate_kind  := id|x|y|z|h|s|sdg|t|tdg|rx|ry|rz|cx|cz|swap|cp
circuit    := circuit(registers, ops)      // ops in source order
```

Arity is a property of `gate_kind` (`gate_arity/1`, `gate_num_params/1` in
circuit.m): 1 qubit for single-qubit kinds, 2 for `cx cz swap cp`; 1 angle for
`rx ry rz cp`, 0 otherwise. The parser builds `unitary` values without arity
checks so that it can report source locations; validate.m rejects wrong arity
with `E-ARITY`. Validation happens before any optimization or emission.

## Invariants (checked by `validate/1`)

1. Every `qubit_ref` names a declared quantum register and `offset < size`.
2. Every `bit_ref` names a declared classical register and `offset < size`.
3. Two-qubit unitaries have distinct operands.
4. A `barrier` has at least one operand.
5. Declared register names are unique across both kinds (E-DUPLICATE).
6. Declarations have size >= 1 (E-SIZE).

## Semantics

- A circuit denotes a sequence of linear maps on the statevector of its quantum
  registers, interleaved with measurements and resets.
- Equality of circuits for transformation checks is defined by the independent
  statevector evaluator (statevector.m). v0 compares statevectors exactly, to
  1e-9 per amplitude, which is stronger than equality up to global phase. Measured
  circuits have no statevector and are not compared by the evaluator.

## Lowering

`emit_qasm/1` (qasm_emit.m) maps the IR to OpenQASM 3 text in the frozen subset. Angles render as
`%.17g` (round-trip exact for IEEE-754 binary64). Composite gates are gone before lowering.
