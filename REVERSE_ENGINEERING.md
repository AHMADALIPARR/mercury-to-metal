# REVERSE_ENGINEERING.md

## Source

Reconstructed from `mercury-to-metal-ab76971.tar.gz` (41 KB, 77 files),
uploaded 2026-10-13. The archive contained no `.git` directory — no commit
history, no author metadata, no timestamps beyond file mtimes.

## What Was Reconstructed

The archive is a **Mercury quantum circuit compiler** with braid-word algebra:

| Component | Files | Lines |
|---|---|---|
| Compiler (Mercury) | `compiler/src/*.m` (9 modules) | 2,350 |
| Braid topology | `topology/braid/braid.m` | 274 |
| Algebraic tests | `tests/algebraic/test_braid.m` | 368 |
| **Total Mercury** | | **2,992** |
| Specifications | `specifications/**/*.md` (11 docs) | — |
| Test corpus | `tests/compiler/corpus/` (valid/invalid/warnings/golden) | — |

## Commit History (Reconstructed)

The 4 commits below are **logical reconstructions**, not the original history.
They reflect the development phases evident in the file structure and specs:

1. **`08d1891` Initial** — Skeleton: README, Makefile, .gitignore
2. **`0032a3f` Specs** — Compiler architecture, semantics, source language,
   QASM subset, braid group spec, Phase I/II acceptance, audit framework
3. **`096ab44` Compiler** — Lexer, parser, circuit IR, validate, optimize,
   QASM emit, statevector, diagnostic, CLI driver
4. **`6082c35` Topology + Tests** — Braid-word algebra, Burau representation,
   algebraic tests, compiler corpus + regression harness

## What the Code Does

- **Compiler:** Parse `.mqc` (Mercury circuit source) → validate → optimize
  (gate cancellation, fusion, broadcast) → emit OpenQASM 3 (frozen subset)
- **Statevector:** Classical simulation for testing — NOT quantum hardware
- **Braid:** Braid-word algebra with Burau representation, verified by tests
- **Interface:** OpenQASM 3 text in the frozen subset (`QASM_SUBSET.md`)

## The Point: Mercury to Metal

The name is the mission. Mercury source → OpenQASM 3 → hardware.

The compiler's OpenQASM 3 output is the handoff to metal: quantum devices,
FPGA controllers, QRNG-driven systems. The frozen QASM subset is the contract
between the compiler and whatever runs the circuits.

## What Is Next

- **Hardware integration:** OpenQASM 3 is ready. The handoff is the goal.
- **Klong numerics:** In progress (see KLONG_STATUS.md).
- **Unitary/Fibonacci braid reps:** Next (see PHASE_II_ACCEPTANCE.md).
- **Native C runtime:** Planned.
- **External QASM validation:** Qiskit/openqasm3 conformance check pending.

See `specifications/audit/AUDIT_REPORT.md` for full gates A-E status.

## Original Session

Per the audit report: built in a single session with Mercury 22.01.9,
POSIX shell, awk. Python used only to edit source files during development,
never by any build or test. The archive hash `ab76971` in the filename
suggests the original commit it was snapshotted from, but the `.git`
directory was not included in the archive.
