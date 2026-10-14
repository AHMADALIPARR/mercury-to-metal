% SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
% Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
% Authored by Ahmad Ali Parr.
% Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

%---------------------------------------------------------------------------%
% braid.m
%
% Symbolic braid words on n strands, and the unreduced Burau representation
% used for numerical checks.
%
% Purpose:    Represent braid-group words, compose and invert them, reduce them
%             by free cancellation, apply the braid relations as explicit
%             rewrite moves, and evaluate the Burau representation.
% Words:      A generator is a nonzero integer g with 1 <= |g| <= n-1. A
%             positive g is sigma_g; a negative g is sigma_|g|^-1. A word is a
%             list of generators read left to right.
% Relations:  sigma_i sigma_i^-1 = 1                       (free cancellation)
%             sigma_i sigma_{i+1} sigma_i = sigma_{i+1} sigma_i sigma_{i+1}
%             sigma_i sigma_j = sigma_j sigma_i for |i-j| >= 2
%             The braid relation holds for signed generators too: inverting both
%             sides gives the relation on the inverse generators, which is the
%             negative-sign form of the same two moves.
% Exactness:  Free cancellation and rewrite moves are exact symbolic operations.
%             Burau matrices use floats; the parameters used in the tests give
%             dyadic entries, and the checks use a tolerance.
% Faithfulness: Equal Burau images are evidence of equality of braids, not a
%             decision of it. Only free cancellation is a decision procedure.
%
% Failures:   Moves that do not match at the given position fail (semidet).
%
%---------------------------------------------------------------------------%

:- module braid.
:- interface.

:- import_module list.

% A braid word on a fixed number of strands. History lists the rewrite moves
% applied, in order.
:- type braid_word
    --->    bw(strands :: int, gens :: list(int), history :: list(string)).

% True if the strand count is at least 2 and every generator is nonzero with
% magnitude at most strands - 1.
:- pred valid_word(braid_word::in) is semidet.

% Inverse word: reverse the order and negate each generator.
:- func inverse(braid_word) = braid_word.

% Concatenation of two words on the same number of strands.
:- pred compose(braid_word::in, braid_word::in, braid_word::out) is semidet.

% Free reduction: delete adjacent pairs g, -g until none remain. Exact.
:- func free_reduce(braid_word) = braid_word.

% Direction of a braid relation: lr rewrites [i, i+1, i] to [i+1, i, i+1];
% rl rewrites the reverse.
:- type direction
    --->    lr
    ;       rl.

:- type move
    --->    braid_relation(int, direction)
    ;       commute.

% Short name recorded in the history.
:- func move_name(move) = string.

% apply_move(Pos, Move, W0, W): apply Move at 0-based position Pos.
:- pred apply_move(int::in, move::in, braid_word::in, braid_word::out)
    is semidet.

% Unreduced Burau matrix of a word at parameter t, as rows.
:- func burau(braid_word, float) = list(list(float)).

% Identity matrix of size n.
:- func identity_matrix(int) = list(list(float)).

% Largest absolute entrywise difference of two n x n matrices.
:- func max_abs_diff(list(list(float)), list(list(float))) = float.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module float.
:- import_module int.
:- import_module string.

valid_word(bw(N, Gens, _)) :-
    N >= 2,
    all_valid(N, Gens).

:- pred all_valid(int::in, list(int)::in) is semidet.

all_valid(_, []).
all_valid(N, [G | Gs]) :-
    G \= 0,
    int.abs(G) =< N - 1,
    all_valid(N, Gs).

inverse(bw(N, Gens, _)) = bw(N, list.map(negate, list.reverse(Gens)), []).

:- func negate(int) = int.

negate(G) = -G.

compose(bw(N, A, _), bw(M, B, _), bw(N, A ++ B, [])) :-
    N = M.

free_reduce(bw(N, Gens, H)) = bw(N, reduce_stack(Gens, []), H).

% Cancel against the top of the stack; the stack holds the reduced prefix in
% reverse.
:- func reduce_stack(list(int), list(int)) = list(int).

reduce_stack([], Stack) = list.reverse(Stack).
reduce_stack([G | Gs], Stack) = Result :-
    ( if Stack = [T | Rest], T = -G then
        Result = reduce_stack(Gs, Rest)
    else
        Result = reduce_stack(Gs, [G | Stack])
    ).

move_name(braid_relation(I, lr)) = "braid(" ++ int_to_string(I) ++ ")".
move_name(braid_relation(I, rl)) = "braid_inv(" ++ int_to_string(I) ++ ")".
move_name(commute) = "commute".

apply_move(Pos, Move, bw(N, Gens, H), bw(N, Gens1, H ++ [move_name(Move)])) :-
    list.split_list(Pos, Gens, Before, After),
    rewrite_head(Move, After, Rewritten),
    Gens1 = Before ++ Rewritten.

% Rewrite the front of the list according to Move.
:- pred rewrite_head(move::in, list(int)::in, list(int)::out) is semidet.

rewrite_head(braid_relation(I, Dir), Gens, Rewritten) :-
    list.split_list(3, Gens, Prefix, Rest),
    braid_pattern(I, Dir, Lhs, Rhs),
    ( if Prefix = Lhs then
        Rewritten = Rhs ++ Rest
    else if Prefix = list.map(negate, Lhs) then
        Rewritten = list.map(negate, Rhs) ++ Rest
    else
        fail
    ).
rewrite_head(commute, Gens, Rewritten) :-
    Gens = [A, B | Rest],
    int.abs(int.abs(A) - int.abs(B)) >= 2,
    Rewritten = [B, A | Rest].

% The three-generator sides of the braid relation for the positive sign. The
% negative sign is the same pattern with every generator negated, which
% rewrite_head checks.
:- pred braid_pattern(int::in, direction::in, list(int)::out, list(int)::out)
    is semidet.

braid_pattern(I, lr, [I, I + 1, I], [I + 1, I, I + 1]) :-
    I >= 1.
braid_pattern(I, rl, [I + 1, I, I + 1], [I, I + 1, I]) :-
    I >= 1.

%---------------------------------------------------------------------------%
% Burau representation

burau(bw(N, Gens, _), T) = burau_loop(N, T, Gens, identity_matrix(N)).

:- func burau_loop(int, float, list(int), list(list(float))) =
    list(list(float)).

burau_loop(_, _, [], M) = M.
burau_loop(N, T, [G | Gs], M) =
    burau_loop(N, T, Gs, mat_mul(M, generator_matrix(N, T, G))).

% Generator matrix for sigma_|G| (G > 0) or its inverse (G < 0).
:- func generator_matrix(int, float, int) = list(list(float)).

generator_matrix(N, T, G) = list.map(gen_row(N, T, G), indices(N)).

:- func gen_row(int, float, int, int) = list(float).

gen_row(N, T, G, R) = list.map(gen_entry(N, T, G, R), indices(N)).

% Entry (R, C) of the generator matrix. The 2 x 2 block sits at 0-based rows
% and columns p = |G| - 1 and q = |G|:
%   sigma:     [[1 - t, t], [1, 0]]
%   sigma^-1:  [[0, 1], [1/t, (t - 1)/t]]
:- func gen_entry(int, float, int, int, int) = float.

gen_entry(_, T, G, R, C) = Value :-
    P = int.abs(G) - 1,
    Q = P + 1,
    ( if G > 0 then
        A = 1.0 - T, B = T, Cc = 1.0, D = 0.0
    else
        A = 0.0, B = 1.0, Cc = 1.0 / T, D = (T - 1.0) / T
    ),
    ( if R = P, C = P then Value = A
    else if R = P, C = Q then Value = B
    else if R = Q, C = P then Value = Cc
    else if R = Q, C = Q then Value = D
    else if R = C then Value = 1.0
    else Value = 0.0
    ).

identity_matrix(N) = list.map(id_row(N), indices(N)).

:- func id_row(int, int) = list(float).

id_row(N, R) = list.map(id_entry(R), indices(N)).

:- func id_entry(int, int) = float.

id_entry(R, C) = ( if R = C then 1.0 else 0.0 ).

:- func mat_mul(list(list(float)), list(list(float))) = list(list(float)).

mat_mul(A, B) = list.map(mul_row(B), A).

:- func mul_row(list(list(float)), list(float)) = list(float).

mul_row(B, Row) = list.map(dot_col(Row), transpose(B)).

:- func dot_col(list(float), list(float)) = float.

dot_col(Row, Col) = dot(Row, Col).

:- func dot(list(float), list(float)) = float.

dot(Xs, Ys) = ( if Xs = [X | Xt], Ys = [Y | Yt] then X * Y + dot(Xt, Yt)
    else 0.0 ).

% Transpose of a square matrix given as rows.
:- func transpose(list(list(float))) = list(list(float)).

transpose(M) = list.map(column(M), indices(list.length(M))).

:- func column(list(list(float)), int) = list(float).

column(M, C) = list.map(nth_float(C), M).

:- func nth_float(int, list(float)) = float.

nth_float(_, []) = 0.0.
nth_float(K, [X | Xs]) = ( if K = 0 then X else nth_float(K - 1, Xs) ).

max_abs_diff(A, B) = max_list(diffs_of_rows(A, B)).

% Absolute entry differences of two row lists, flattened.
:- func diffs_of_rows(list(list(float)), list(list(float))) = list(float).

diffs_of_rows([], _) = [].
diffs_of_rows([_ | _], []) = [].
diffs_of_rows([R | Rs], [S | Ss]) = diffs_of_row(R, S) ++ diffs_of_rows(Rs, Ss).

:- func diffs_of_row(list(float), list(float)) = list(float).

diffs_of_row([], _) = [].
diffs_of_row([_ | _], []) = [].
diffs_of_row([X | Xs], [Y | Ys]) = [float.abs(X - Y) | diffs_of_row(Xs, Ys)].

:- func max_list(list(float)) = float.

max_list([]) = 0.0.
max_list([X | Xs]) = ( if X >= max_list(Xs) then X else max_list(Xs) ).

:- func indices(int) = list(int).

indices(N) = ( if N =< 0 then [] else indices_from(0, N) ).

:- func indices_from(int, int) = list(int).

indices_from(K, N) = ( if K >= N then [] else [K | indices_from(K + 1, N)] ).

%---------------------------------------------------------------------------%
:- end_module braid.
%---------------------------------------------------------------------------%
