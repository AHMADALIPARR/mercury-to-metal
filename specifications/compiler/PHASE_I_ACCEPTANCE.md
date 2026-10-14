# Phase I Acceptance: Mercury Symbolic Circuit Compiler

Status: **ACCEPTED for v0 scope**, with the limitations in COMPILER_LIMITATIONS.md.

## Evidence

Build (run from repository root):

```
make compiler           # mmc --make mercury_qc, then copy to compiler/bin/
make test-compiler      # sh tests/compiler/run_tests.sh compiler/bin/mercury-qc
```

Last run: `passed: 255`, `failed: 0`. The 255 checks are:

| Category | Count | What it verifies |
|---|---|---|
| valid corpus: check | 7 | circuits in `tests/compiler/corpus/valid` validate |
| valid corpus: roundtrip | 7 | emitted QASM parses and re-emits identically |
| determinism | 14 | `-O0` and `-O1` byte-identical across runs |
| golden output | 7 | `-O1` emission equals `corpus/golden/*.qasm` (hand-reviewed) |
| invalid corpus | 16 | each rejected with its expected code (exit 1) |
| semantics | 4 | statevector of `-O0` and `-O1` agree (1e-9) |
| property sweep | 200 | seeded random unitary circuits, same comparison plus roundtrip |

Bell state: `compiler/bin/mercury-qc statevector` on H + CX gives amplitudes
0.70710678 at |00> and |11>, zero elsewhere, matching (|00> + |11>)/sqrt(2).

Hand-checked optimizer output: `fuse.mqc` gives `rz(0.7)` (0.3 + 0.4),
`rx(-1)` (-1.25 + 0.25), and `cp(pi/2)` (pi/4 + pi/4 with reversed operands);
`cancel.mqc` reduces to the empty circuit.

## Gate A / B / D relation

- Gate A (toolchain): `mmc` compiled and ran a minimal module.
- Gate B (compiler): a Mercury-authored circuit compiles to OpenQASM 3 in the frozen
  subset. Validated by the compiler's own parser and statevector evaluator, not by
  an external OpenQASM toolchain (none is available; see limitation 8).
- Gate D (integration): deterministic regression tests pass.

## Items not claimed

- Formal verification: none. Tests are numerical and by example.
- External toolchain conformance: not run.
- Performance: no benchmark has been run for the compiler.
