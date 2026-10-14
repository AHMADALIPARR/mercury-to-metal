# Braid Group Specification (topology/braid/braid.m)

## Objects

- A braid word is `bw(strands, gens, history)`. `strands >= 2`.
- A generator is a nonzero integer `g` with `1 <= |g| <= strands - 1`:
  `g > 0` is sigma_g, `g < 0` is sigma_|g|^-1.
- `history` lists the rewrite moves applied, in order.

## Operations and their status

| Operation | Evidence class | Notes |
|---|---|---|
| `valid_word` | exact | rejects 0, out-of-range generators, fewer than 2 strands |
| `inverse` | exact | reverse and negate |
| `compose` | exact | strand counts must match (semidet) |
| `free_reduce` | exact, decision procedure | stack cancellation of adjacent g, -g. Reduced word is the unique free-reduced form of the free group word. It decides equality only in the free group, not in the braid group. |
| `apply_move` | exact rewrite | three move kinds, below |
| `burau` | numeric | unreduced Burau at parameter t, float |

## Rewrite moves

- `braid_relation(i, lr)`: `[i, i+1, i]` -> `[i+1, i, i+1]`, and for negative
  signs `[-i, -(i+1), -i]` -> `[-(i+1), -i, -(i+1)]`.
- `braid_relation(i, rl)`: the reverse of the above.
- `commute`: adjacent `[a, b]` -> `[b, a]` when the magnitudes differ by at least 2.

Each move is a valid consequence of the braid relations. Sign-reversed forms are
the inverted relations. A move applied at a position either matches exactly or
fails; nothing else is rewritten.

## What this module does not do

- It does not decide braid-word equality. Only free cancellation is a decision
  procedure, and it decides only the free-group word problem. Two braid words may
  be equal in B_n and still have different free reductions, and the module does not
  search for such equalities.
- It does not canonicalize. There is no normal form.
- No Garside or Dehornoy normal form is implemented.

## Burau representation

The unreduced Burau matrices for sigma_i on n strands, at parameter t:

- sigma_i: identity except the 2x2 block at rows and columns i, i+1 equal to
  `[[1-t, t], [1, 0]]`;
- sigma_i^{-1}: the same block replaced by `[[0, 1], [1/t, (t-1)/t]]`.

Burau is a homomorphism from the braid group to GL_n for every t. It is not known to
be faithful for n >= 5, and the module makes no faithfulness claim. Equal images are
evidence of equality, never a decision. Unitary Burau is not implemented: at real t
the matrices are not unitary, and no unitary representation has been built.

## Tests

tests/algebraic/test_braid.m (32 checks, all passing): free reduction fixtures,
validity, inverse fixtures, `w w^-1 = I` in the Burau image for 40 random words at
four parameters, Artin relations at four parameters, distant commutation,
non-vacuity checks, and a move-soundness sweep over random words on 3, 4 and 5
strands. The sweep counts applications, so it cannot pass with no moves applied.
