# Mercury-to-Metal Circuit Source Language (v0)

Scope: the input language of `mercury-qc`. Everything emitted must lie inside
`specifications/interchange/QASM_SUBSET.md`.

## Lexical

- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`, not a keyword.
- Integers: decimal `[0-9]+`. Reals: `[0-9]+\.[0-9]*([eE][-+]?[0-9]+)?` or `[0-9]+[eE][-+]?[0-9]+`.
- Comments: `//` to end of line.
- Punctuation: `( ) [ ] { } , ; = -> * /`.
- Every token carries line and column (1-based).

## Grammar

```
program   := decl* stmt*
decl      := "qubit" "[" INT "]" IDENT ";"
           | "bit" "[" INT "]" IDENT ";"
           // composite gate definitions are reserved and rejected in v0
stmt      := gatecall ";"
           | IDENT "[" INT "]" "=" "measure" qref ";"    // classical destination
           | IDENT "=" "measure" qref ";"                // broadcast measurement
           | "reset" qref ";"
           | "barrier" qref ("," qref)* ";"
gatecall  := IDENT ("(" angle ")")? qref ("," qref)*
qref      := IDENT "[" INT "]"
angle     := real | "pi" | "-" "pi" | real "*" "pi" | "pi" "/" real
```

Declarations may appear anywhere, but a register must be declared before any
statement that uses it; use before declaration is `E-UNDECLARED`. Redeclaration of
any name is `E-DUPLICATE`.

Broadcast: a whole-register operand (`h q;`, `reset q;`, `barrier q;`,
`c = measure q;`) is expanded by the parser; see SEMANTICS.md.

## Gate definitions (not implemented in v0)

`gate name(...) ... { ... }` definitions are rejected with `E-UNSUPPORTED`. The
planned semantics (inlining at call sites before validation, no recursion) are
recorded in COMPILER_LIMITATIONS.md as future work. v0 therefore has no user-defined
composite gates.

## Built-in gates

Exactly the frozen subset: `id x y z h s sdg t tdg rx ry rz cx cz swap cp`.
Two-qubit gates require distinct operands.

## Semantics notes

- `measure` and `reset` are nonunitary. No transformation may move a unitary gate
  across a measurement or reset on the same qubit.
- `barrier` is a reordering fence on its operands. It has no unitary effect.
- A bit read is never performed in the source language; bits are write-only outputs
  of measurement. A bit written twice is allowed and records the last value; the
  compiler emits a warning diagnostic for this.
