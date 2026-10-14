# Mercury Circuit Compiler: Architecture

Language: Mercury 22.01.9 (built from source; `mmc` at `~/.local/mercury/bin`).
No Python, JavaScript or other language is used in `compiler/`.

## Pipeline

```
source text
  -> lexer.m        tokens with line:column
  -> parser.m       circuit (items in source order), broadcasts expanded
  -> validate.m     diagnostics: bounds, arity, declarations, operands, bits
  -> optimize.m     peephole rewrites (-O1 only)
  -> qasm_emit.m    OpenQASM 3 text (frozen subset)
statevector.m       independent evaluator, used by tests and the CLI
diagnostic.m        located, coded diagnostics
circuit.m           IR types and gate table
mercury_qc.m        CLI driver
```

Validation runs before optimization and emission. The optimizer and emitter
assume a validated circuit. The statevector evaluator takes the same IR, so it
checks the optimizer's output independently of the emitter's text.

## Module contracts

| Module | Input | Output | Failure mode |
|---|---|---|---|
| lexer | string | `lex_ok(tokens)` / `lex_err` | `E-LEX` |
| parser | string | `parse_ok(circuit)` / `parse_fail(diags)` | `E-SYNTAX`, `E-UNSUPPORTED`, `E-UNDECLARED`, `E-BROADCAST` |
| validate | circuit | diagnostics (errors and warnings) | never fails |
| optimize | validated circuit | circuit with same unitary | never fails |
| qasm_emit | validated circuit | text | unspecified if not validated |
| statevector | unitary circuit | amplitudes | `sv_err` for nonunitary or > 20 qubits |

## Boundaries

- The compiler does not depend on the braid module, the runtime, hardware or
  Qiskit. Its only external interface is the OpenQASM 3 text.
- Dispatch in parser.m and validate.m uses if-then-else on pattern tests, not
  disjunctions over overlapping patterns, so every predicate is det.
- Lists are used throughout. Circuits in scope are small; the statevector
  evaluator is the only place with large data (an array of 2^n amplitudes).

## Build

`make -C compiler` runs `mmc --make mercury_qc` in `compiler/src` and copies the
executable to `compiler/bin/mercury-qc`.
