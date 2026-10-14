# Compiler Semantics

## Meaning of a circuit

A validated circuit denotes a sequence of operations over registers:
unitaries, `measure` (quantum to classical bit), `reset`, and `barrier`
(a scheduling fence with no effect on the state). A unitary circuit denotes a
single unitary on the quantum register, with qubit `offset(reg) + index` as
bit position `offset` in the basis index (little-endian).

Gate matrices are standard (statevector.m): `rz(t) = diag(e^{-it/2}, e^{it/2})`,
`rx(t)`, `ry(t)` as usual, `cp(t) = diag(1, 1, 1, e^{it})`, `cx` controlled on the
first operand, `swap` and `cz` symmetric.

## Broadcast (parser.m)

- `g a, b;` with whole registers of equal length `L` expands to `L` gates,
  position `k` applying to `a[k], b[k]`. An indexed operand is fixed.
- Whole registers of different lengths: `E-BROADCAST`.
- `reset q;` expands to one reset per qubit.
- `barrier q;` is one barrier over every qubit of `q`.
- `c = measure q;` measures pairwise; sizes must match (`E-BROADCAST`).

## Optimization (optimize.m), semantics-preserving

Only adjacent operations in the already-optimized sequence are combined, so no
operation moves past another. Rules:

| Rule | Rewrite | Condition |
|---|---|---|
| R1 | `id` removed | always |
| R2 | `rx(0)`, `ry(0)`, `rz(0)`, `cp(0)` removed | angle exactly 0.0 |
| R3 | `g g` removed | g in {x, y, z, h, cx, cz, swap}, same operands (reversed allowed for cz, swap) |
| R4 | `s sdg`, `sdg s`, `t tdg`, `tdg t` removed | same qubit |
| R5 | `rx(a) rx(b)` -> `rx(a+b)`; likewise ry, rz, cp | same operands (reversed allowed for cp) |

R2 is exact. R3 and R4 are exact identities. R5 is exact in real arithmetic; in
binary64 the fused angle may differ from the two-step result by one rounding of
the sum, which the statevector comparison (1e-9) accepts.

Measure, reset and barrier are never rewritten, and nothing combines across them.

The optimizer does not commute non-adjacent operations. Reducible pairs separated
by disjoint gates are left in place. This is a deliberate limit, recorded in
COMPILER_LIMITATIONS.md.

## Validation (validate.m)

Invariants and codes are listed in validate.m's header. Validation reports every
violation, not only the first. Warnings (`W-...`) do not make a circuit invalid.

## Determinism

Output depends only on the input text. The emitter uses `%.17g` for angles, which
round-trips binary64 exactly. Tests check two runs for byte-identical output.
