<!-- SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001 -->
<!-- Copyright (c) 2026 Ahmad Ali Parr. All rights reserved. -->
<!-- Authored by Ahmad Ali Parr. -->
<!-- Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE. -->

# mercury-to-metal

A Mercury circuit compiler, with a symbolic braid-word algebra. Hardware integration
is not present: no quantum or FPGA device is available in this environment.

## Status

| Area | Status | Where |
|---|---|---|
| Mercury circuit compiler (parse, validate, optimize, OpenQASM 3 emit) | working, tested | `compiler/`, `specifications/compiler/` |
| Braid-word algebra and Burau checks (Mercury) | working, tested | `topology/braid/`, `tests/algebraic/` |
| Klong numerics | **blocked**: no Klong available | `specifications/topology/KLONG_STATUS.md` |
| Unitary and Fibonacci braid representations | not built | `specifications/topology/PHASE_II_ACCEPTANCE.md` |
| Native C runtime | not built, and not planned in this session | none |
| Hardware controller, FPGA, QRNG | **blocked**: no device | `specifications/audit/AUDIT_REPORT.md` |

## Build and test

```
make compiler        # builds compiler/bin/mercury-qc (requires mmc)
make test            # compiler regression and semantics, then braid algebra
```

Requirements: Mercury 22.01.9 (`mmc`), POSIX shell, awk. Mercury was built from the
official source distribution into `~/.local/mercury`.

## Layout

- `specifications/interchange/QASM_SUBSET.md`: frozen OpenQASM 3 subset, the only
  interface between the compiler and any consumer.
- `compiler/src/`: Mercury sources. `compiler/bin/mercury-qc` is the CLI.
- `tests/compiler/`: corpus and `run_tests.sh`.
- `topology/braid/`: braid words and Burau representation (Mercury).
- `tests/algebraic/`: braid algebra tests (Mercury).
- `specifications/`: compiler, topology, interchange, and audit documents.

## Limits

Read `specifications/compiler/COMPILER_LIMITATIONS.md` and
`specifications/audit/AUDIT_REPORT.md` before relying on any claim here. In
particular: the statevector evaluator is a classical simulation used for testing, and
nothing in this repository runs on quantum hardware.
