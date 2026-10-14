<!-- SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001 -->
<!-- Copyright (c) 2026 Ahmad Ali Parr. All rights reserved. -->
<!-- Authored by Ahmad Ali Parr. -->
<!-- Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE. -->

# Compiler Limitations (v0)

Each item is a known gap. Each is either rejected with a diagnostic or is a
documented restriction; none is silently substituted.

1. **No user-defined composite gates.** `gate ... { }` is rejected (`E-UNSUPPORTED`).
   The planned semantics are inlining before validation, no recursion.
2. **No classical control, timing, pulse calibration, or custom gates** beyond the
   frozen subset. These are rejected per QASM_SUBSET.md.
3. **Lexing precedes parsing.** The whole input is tokenized first, so a character
   outside the lexical set produces `E-LEX` even where a keyword would have produced
   `E-UNSUPPORTED` (for example `defcal $0`). The construct is still rejected.
4. **Parsing stops at the first syntax error.** Semantic errors are all reported,
   syntax errors are not. Recovery is not implemented.
5. **Optimization is local.** The optimizer does not commute operations, so it does
   not find every reducible pair. It is not a canonicalizer: equal circuits may get
   different outputs.
6. **Bit assignment is write-only.** Bits are not read in the language, so there
   are no measurement-dependency checks beyond declaration and bounds. A repeated
   assignment is reported as `W-BIT-REWRITE`.
7. **Statevector evaluator limits.** At most 20 qubits (2^20 amplitudes, 16 MiB).
   It rejects measurement and reset, so measured circuits are not compared
   semantically. Compared with a tolerance of 1e-9 per amplitude; floating-point
   error grows with circuit length.
8. **No Qiskit or external OpenQASM validator.** Conformance is checked by the
   compiler's own parser and by round-trip tests. Qiskit is not installed here, so
   no independent OpenQASM 3 toolchain has been run against the output. This is the
   weakest point of the interchange evidence.
9. **Angles are float.** No exact rational representation of multiples of pi. The
   emitter writes the rounded value.
10. **Diagnostics for index errors are reported by the validator, not the parser,**
    except broadcast-length and undeclared-register errors.
