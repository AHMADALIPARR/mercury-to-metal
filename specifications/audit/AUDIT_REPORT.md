# Audit Report: Verification and Integration (Gates A-E)

Scope: the state of the repository at the end of this session, checked against the
resume authorization (compiler and mathematics only; no hardware, no C runtime).

## 1. Existing C files and their responsibilities

None. `git ls-files` and `find` show no `.c` or `.h` file in the repository, and the
only C files on the machine are Mercury's own generated sources, outside the repo.
The earlier C runtime work was never written into the repository. Nothing needs to
be classified REAL, SIMULATION, STUB or UNSUPPORTED.

## 2. Simulated hardware, mocks, fabricated interfaces

- No hardware, device, register or DMA code exists in the repository.
- The statevector evaluator (compiler/src/statevector.m) is a classical simulation.
  It is a reference for testing the compiler and is labeled as such. It is not
  quantum hardware and is not used for any hardware claim.
- No test uses a mock. Compiler tests run the real executable on real files; braid
  tests run real Mercury code.

## 3. Interfaces and dependencies

- Compiler: Mercury 22.01.9 standard library only.
- Braid: Mercury standard library only.
- Tests: POSIX shell, awk, cmp, sed, mktemp. No Python in the repository (Python was
  used only to edit source files during development, never by any build or test).
- Interface between compiler and everything else: OpenQASM 3 text in the frozen
  subset (specifications/interchange/QASM_SUBSET.md).

## 4. Hardware operations demonstrated

None. There is no device. Gate E is BLOCKED (see section 7).

## 5. OpenQASM 3 contract compliance

Checked against QASM_SUBSET.md by the regression suite:

| Contract item | Evidence |
|---|---|
| Header and optional stdgates include | roundtrip of corpus files; `include "other.inc"` rejected |
| qubit/bit declarations, sized and single | `qubit q;`, `qubit[2] q;` accepted; size 0 rejected |
| Gate table | every gate used in corpus and property sweep (`id x y z h s sdg t tdg rx ry rz cx cz swap cp`) |
| Angle forms | `angles.mqc` covers real, `-pi`, `pi/2`, `0.5*pi`, `pi*0.25`, exponent; `2+3`, `pi*pi`, `pi/0` rejected |
| Measure, reset, barrier | `bell`, `broadcast`, `ghz3` corpus files |
| Broadcast | `broadcast.mqc`; mismatched sizes rejected |
| Unsupported constructs | `if`, `gate`, `const`, `input`, `delay`, `defcal`, unknown gates, `u3`, `ccx`, `sx`: rejected with E-UNSUPPORTED (defcal with `$` gives E-LEX first; see COMPILER_LIMITATIONS.md item 3) |
| Emission rules | golden outputs; determinism tests; `%.17g` angles |

Not checked: conformance against an external OpenQASM 3 parser. None is installed
(Qiskit and the openqasm3 Python package are not present). This is the main open
evidence gap for Gate B.

## 6. Module boundaries and traceability

- compiler/src imports only its own modules and the standard library. Verified by
  grepping `import_module` in every module.
- topology/braid imports only the standard library and is not imported by the compiler.
- tests/algebraic and tests/compiler reference the implementation only through the
  built executable or the module source staged into a build directory.
- Diagnostic codes: every code in diagnostic.m's header is produced by at least one
  corpus file, including the warning W-BIT-REWRITE (corpus/warnings).
- Golden files were produced by the compiler and then hand-reviewed; the review is
  recorded in PHASE_I_ACCEPTANCE.md.

## 7. Gate status

| Gate | Status | Evidence |
|---|---|---|
| A toolchain | **PASS** | `mmc --make` built `mercury_qc`; a minimal module compiled and ran |
| B compiler | **PASS, with gap** | Bell circuit compiles to OpenQASM 3 in the frozen subset; external toolchain not run |
| C mathematics | **PASS (numeric)** | `make test-algebra`: 32 tests; mutation checks catch broken rewrites |
| D integration | **PASS** | `make test-compiler`: 256 checks, 0 failed |
| E hardware | **BLOCKED** | no quantum or FPGA device present (PCI scan and device nodes checked earlier); no device documentation available |

## 8. Corrections made during this audit

Defects found and fixed while building, each now covered by the suite:

- Lexer: `2+3` lexed as one malformed real; the sign is now part of a literal only
  after an exponent marker. A dangling exponent (`1e`) was read as `1`; it is now a
  syntax error.
- Angles: an expression outside the grammar (`rz(2+3)`) gave a generic syntax error;
  it now gives `E-UNSUPPORTED`, as the contract requires.
- Validation warnings were dropped on valid circuits; they are now printed.
- Specs: SOURCE_LANGUAGE.md and CIRCUIT_IR.md described composite gates and function
  names that the implementation does not have; both now describe what is built.

## 9. Not verified

- No formal proof of any property.
- No external OpenQASM toolchain conformance.
- No benchmarks.
- No Klong numerics.
