# OpenQASM 3 Supported Subset (frozen interface contract)

Status: FROZEN for the first build. Changes require a documented revision of this file
and coordinated updates in `compiler/` (emitter), `interchange/openqasm3/` (importer)
and `runtime/native-c/` (reference executor).

This subset is the only interchange surface between the Mercury compiler and the native
runtime. Anything outside it MUST be rejected with a diagnostic of the form
`UNSUPPORTED <construct> at line:col` (no silent substitution).

## Header

```
OPENQASM 3.0;
include "stdgates.inc";     // optional; the only accepted include
```

Any other `include` is rejected.

## Declarations

- `qubit[N] name;` with N >= 1 (single-qubit `qubit name;` is accepted as N = 1).
- `bit[M] name;` with M >= 1 (single-bit `bit name;` accepted as M = 1).
- Names: `[A-Za-z_][A-Za-z0-9_]*`, not a keyword.
- Declarations must precede use. Redeclaration is an error.

## Qubit and bit references

- `name[i]` with `0 <= i < N` (bounds checked, index is a decimal integer literal).
- Bare `name` is accepted only where it denotes the whole register in a broadcast
  (`h q;` applies H to every qubit of `q`). Broadcast over registers of different
  lengths for two-qubit gates is an error.

## Gates

| Gate   | Arity | Parameters | Notes |
|--------|-------|------------|-------|
| `id`   | 1 | 0 | identity |
| `x`, `y`, `z` | 1 | 0 | Pauli |
| `h`    | 1 | 0 | Hadamard |
| `s`, `sdg`, `t`, `tdg` | 1 | 0 | phase and adjoints |
| `rx(θ)`, `ry(θ)`, `rz(θ)` | 1 | 1 | rotation about X, Y, Z |
| `cx`   | 2 | 0 | control first, target second |
| `cz`   | 2 | 0 | symmetric |
| `swap` | 2 | 0 | symmetric |
| `cp(θ)` | 2 | 1 | controlled phase, diag(1,1,1,e^{iθ}) |

Distinct qubit operands are required for two-qubit gates (`cx q[0], q[0];` is an error).

## Angles

Accepted angle forms:

- real literal, e.g. `0.5`, `-1.25e-3`
- `pi`
- `-pi`
- `k*pi` or `pi*k` where k is a real literal
- `pi/k` where k is a nonzero real literal

Other expressions (variables, function calls, arithmetic beyond the above) are rejected.

## Measurement and reset

- `c[i] = measure q[j];` (single-qubit, classical destination)
- `reset q[j];`
- Broadcast forms `c = measure q;` are accepted when the register lengths match.

## Barrier

- `barrier q[...];` or `barrier q;` — a scheduling marker with no unitary effect.

## Comments

- `//` line comments and `/* ... */` block comments.

## Explicitly unsupported (must produce `UNSUPPORTED` diagnostics)

- Classical control: `if`, `while`, `for`, `else`, branching on bits.
- `gate` definitions in imported files (composite gates are expanded by the compiler
  before emission, so emitted files never contain them).
- `delay`, `box`, `durationof`, timing literals, `stretch`.
- `input`, `output`, `const`, `def`, `extern`, `let`, `array` types.
- Pulse-level `defcal`, `cal`, `defcalgrammar`.
- Gates outside the table above, including `u1`, `u2`, `u3`, `sx`, `ccx`, `ry`-like
  unlisted gates, `cu`, custom names.
- Expressions outside the angle grammar above.
- Qubit allocation with non-literal sizes.

## Emission rules (Mercury compiler)

- Header first, then `qubit`/`bit` declarations, then operations in source order.
- Angles are emitted with `%.17g` (round-trip exact for IEEE double).
- Output is byte-deterministic for a given input and compiler version: no timestamps,
  no hash-table iteration order, LF line endings, single trailing newline.
- Composite gates are inlined; emitted programs contain no `gate` definitions.

## Semantics

- Program state is a pure unitary sequence followed by measurements and resets.
- `measure` collapses the state and writes the outcome to the named bit.
- Global phase is not observable and is not tracked by the runtime.
