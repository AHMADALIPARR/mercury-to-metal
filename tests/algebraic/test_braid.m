% SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
% Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
% Authored by Ahmad Ali Parr.
% Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

%---------------------------------------------------------------------------%
% test_braid.m
%
% Algebraic tests for topology/braid/braid.m.
%
% Output: "PASS name" or "FAIL name: detail" per test, then a summary line.
% Exit status 1 if any test fails. Random words come from a fixed linear
% congruential generator, so runs are reproducible.
%
% Evidence classes, reported with each test name:
%   exact    free reduction, inverses, validity, rewrite positions
%   numeric  Burau image equality within TOL
%
%---------------------------------------------------------------------------%

:- module test_braid.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module bool.
:- import_module braid.
:- import_module float.
:- import_module int.
:- import_module list.
:- import_module require.
:- import_module string.

% Tolerance for Burau image comparisons.
:- func tol = float.

tol = 1.0e-9.

% Burau parameters. All are exactly representable.
:- func params = list(float).

params = [2.0, 3.0, 0.5, -1.0].

main(!IO) :-
    Results = list.condense([
        free_reduction_results,
        validity_results,
        inverse_results,
        burau_identity_results,
        relation_results,
        move_soundness_results,
        non_vacuity_results
    ]),
    list.foldl(report, Results, !IO),
    Failures = list.filter(is_fail, Results),
    io.format("%d tests, %d failed\n",
        [i(list.length(Results)), i(list.length(Failures))], !IO),
    ( if Failures = [] then
        true
    else
        io.set_exit_status(1, !IO)
    ).

:- type test_result
    --->    pass(string)
    ;       fail(string, string).

:- pred is_fail(test_result::in) is semidet.

is_fail(fail(_, _)).

:- pred report(test_result::in, io::di, io::uo) is det.

report(pass(Name), !IO) :-
    io.format("PASS %s\n", [s(Name)], !IO).
report(fail(Name, Detail), !IO) :-
    io.format("FAIL %s: %s\n", [s(Name), s(Detail)], !IO).

% A test test_result from a boolean condition.
:- func result_of(string, bool) = test_result.

result_of(Name, yes) = pass(Name).
result_of(Name, no) = fail(Name, "condition does not hold").

:- func word(int, list(int)) = braid_word.

word(N, Gens) = bw(N, Gens, []).

:- func fmt(float) = string.

fmt(T) = string.format("%g", [f(T)]).

%---------------------------------------------------------------------------%
% Free reduction (exact)

:- func free_reduction_results = list(test_result).

free_reduction_results = [
    result_of("exact: reduce [1,-1,2,2,-2] = [2]",
        ( if free_reduce(word(3, [1, -1, 2, 2, -2])) = word(3, [2]) then
            yes else no )),
    result_of("exact: reduce [1,2,-2,-1] = []",
        ( if free_reduce(word(3, [1, 2, -2, -1])) = word(3, []) then
            yes else no )),
    result_of("exact: reduce [1,1,-1,-1] = []",
        ( if free_reduce(word(3, [1, 1, -1, -1])) = word(3, []) then
            yes else no )),
    result_of("exact: reduce [1,2,1] unchanged",
        ( if free_reduce(word(3, [1, 2, 1])) = word(3, [1, 2, 1]) then
            yes else no ))
].

%---------------------------------------------------------------------------%
% Validity (exact)

:- func validity_results = list(test_result).

validity_results = [
    result_of("exact: [1,2,-1] valid on 3 strands",
        ( if valid_word(word(3, [1, 2, -1])) then yes else no )),
    result_of("exact: reject generator 0",
        ( if valid_word(word(3, [0])) then no else yes )),
    result_of("exact: reject sigma_3 on 3 strands",
        ( if valid_word(word(3, [3])) then no else yes )),
    result_of("exact: reject sigma_-3 on 3 strands",
        ( if valid_word(word(3, [-3])) then no else yes )),
    result_of("exact: reject a single strand",
        ( if valid_word(word(1, [])) then no else yes ))
].

%---------------------------------------------------------------------------%
% Inverses and composition (exact)

:- func inverse_results = list(test_result).

inverse_results = [
    result_of("exact: inverse [1,2,-2] = [2,-2,-1]",
        ( if inverse(word(3, [1, 2, -2])) = word(3, [2, -2, -1]) then
            yes else no )),
    result_of("exact: w * w^-1 reduces to the empty word",
        ( if free_reduce(compose_words(word(3, [1, 2, 2, -1]),
                inverse(word(3, [1, 2, 2, -1])))) = word(3, []) then
            yes else no ))
].

:- func compose_words(braid_word, braid_word) = braid_word.

compose_words(A, B) = C :-
    ( if compose(A, B, C0) then
        C = C0
    else
        error("compose_words: strand counts differ")
    ).

%---------------------------------------------------------------------------%
% Random words (fixed seed)

% Next pseudo-random value.
:- pred lcg(int::in, int::out) is det.

lcg(S, S1) :-
    S1 = (1103515245 * S + 12345) mod 2147483648.

% A word of length Len on N strands, drawn from seed S0; returns the new seed.
:- pred random_word(int::in, int::in, int::in, braid_word::out, int::out)
    is det.

random_word(N, Len, S0, bw(N, Gens, []), S) :-
    random_gens(N, Len, S0, Gens, S).

:- pred random_gens(int::in, int::in, int::in, list(int)::out, int::out)
    is det.

random_gens(N, Len, S0, Gens, S) :-
    ( if Len =< 0 then
        Gens = [],
        S = S0
    else
        lcg(S0, S1),
        Mag = 1 + (S1 div 65536) mod (N - 1),
        lcg(S1, S2),
        ( if (S2 div 65536) mod 2 = 0 then
            Sign = 1
        else
            Sign = -1
        ),
        random_gens(N, Len - 1, S2, Rest, S),
        Gens = [Sign * Mag | Rest]
    ).

% Count random words of length Len on N strands from seed Seed.
:- func random_words(int, int, int, int) = list(braid_word).

random_words(N, Count, Len, Seed) = Words :-
    random_words_loop(N, Count, Len, Seed, Words).

:- pred random_words_loop(int::in, int::in, int::in, int::in,
    list(braid_word)::out) is det.

random_words_loop(N, Count, Len, S0, Words) :-
    ( if Count =< 0 then
        Words = []
    else
        random_word(N, Len, S0, W, S1),
        random_words_loop(N, Count - 1, Len, S1, Rest),
        Words = [W | Rest]
    ).

%---------------------------------------------------------------------------%
% Burau representation (numeric)

:- func burau_identity_results = list(test_result).

burau_identity_results = list.map(burau_identity_result, params).

% For each parameter, w * w^-1 has the identity Burau image for all sampled w.
:- func burau_identity_result(float) = test_result.

burau_identity_result(T) = Result :-
    Words = random_words(4, 40, 8, 7),
    Name = "numeric: Burau w*w^-1 = I, t=" ++ fmt(T) ++ ", 40 words",
    ( if list.all_true(identity_pair_ok(T), Words) then
        Result = pass(Name)
    else
        Result = fail(Name, "some w*w^-1 image differs from I")
    ).

:- pred identity_pair_ok(float::in, braid_word::in) is semidet.

identity_pair_ok(T, W) :-
    N = W ^ strands,
    Prod = compose_words(W, inverse(W)),
    max_abs_diff(burau(Prod, T), identity_matrix(N)) < tol.

%---------------------------------------------------------------------------%
% Braid relations (numeric)

:- func relation_results = list(test_result).

relation_results = list.condense(list.map(relation_checks, params)).

:- func relation_checks(float) = list(test_result).

relation_checks(T) = [
    numeric_equal("numeric: Artin 1-2-1 = 2-1-2, t=" ++ fmt(T),
        burau(word(3, [1, 2, 1]), T), burau(word(3, [2, 1, 2]), T)),
    numeric_equal("numeric: inverse Artin relation, t=" ++ fmt(T),
        burau(word(3, [-1, -2, -1]), T), burau(word(3, [-2, -1, -2]), T)),
    numeric_equal("numeric: sigma_1 and sigma_3 commute on 4 strands, t="
        ++ fmt(T),
        burau(word(4, [1, 3]), T), burau(word(4, [3, 1]), T))
].

:- func numeric_equal(string, list(list(float)), list(list(float))) = test_result.

numeric_equal(Name, A, B) = ( if max_abs_diff(A, B) < tol then
    pass(Name)
  else
    fail(Name, "Burau images differ") ).

%---------------------------------------------------------------------------%
% Rewrite moves preserve the Burau image at every position where they apply.
% The sweep also counts applications, so a pass cannot be vacuous.

:- type sweep
    --->    sweep(applied :: int, violations :: int).

:- type candidate
    --->    candidate(int, move).

:- func move_soundness_results = list(test_result).

move_soundness_results = [
    move_result(3, 11, "braid moves on 3 strands"),
    move_result(4, 12, "braid and commute moves on 4 strands"),
    move_result(5, 13, "braid and commute moves on 5 strands")
].

:- func move_result(int, int, string) = test_result.

move_result(N, Seed, Label) = Result :-
    Words = random_words(N, 30, 10, Seed),
    list.foldl(sweep_word_into(0.5), Words, sweep(0, 0), Total),
    Name = "numeric: moves sound (" ++ Label ++ "), applied="
        ++ int_to_string(Total ^ applied),
    ( if Total ^ violations = 0, Total ^ applied > 0 then
        Result = pass(Name)
    else
        Result = fail(Name, int_to_string(Total ^ violations)
            ++ " violation(s), applied=" ++ int_to_string(Total ^ applied))
    ).

:- pred sweep_word_into(float::in, braid_word::in, sweep::in, sweep::out)
    is det.

sweep_word_into(T, W, !S) :-
    Cands = candidates(W),
    list.foldl(sweep_candidate(T, W), Cands, !S).

:- pred sweep_candidate(float::in, braid_word::in, candidate::in,
    sweep::in, sweep::out) is det.

sweep_candidate(T, W, candidate(Pos, Move), sweep(A0, V0), Sweep) :-
    ( if apply_move(Pos, Move, W, W1) then
        Diff = max_abs_diff(burau(W, T), burau(W1, T)),
        ( if Diff < tol then
            V = V0
        else
            V = V0 + 1
        ),
        Sweep = sweep(A0 + 1, V)
    else
        Sweep = sweep(A0, V0)
    ).

% Every (position, move) pair for the word, whether or not the move applies.
:- func candidates(braid_word) = list(candidate).

candidates(W) = list.condense(list.map(pos_candidates(moves_for(W ^ strands)),
    indices(list.length(W ^ gens)))).

:- func pos_candidates(list(move), int) = list(candidate).

pos_candidates(Moves, Pos) = list.map(candidate_at(Pos), Moves).

:- func candidate_at(int, move) = candidate.

candidate_at(Pos, M) = candidate(Pos, M).

% All moves for n strands: commutation, and both directions of each braid
% relation with i from 1 to n-2.
:- func moves_for(int) = list(move).

moves_for(N) = [commute | list.condense(list.map(braid_moves,
    indices_from(1, N - 1)))].

:- func braid_moves(int) = list(move).

braid_moves(I) = [braid_relation(I, lr), braid_relation(I, rl)].

:- func indices(int) = list(int).

indices(N) = ( if N =< 0 then [] else indices_from(0, N) ).

:- func indices_from(int, int) = list(int).

indices_from(K, N) = ( if K >= N then [] else [K | indices_from(K + 1, N)] ).

%---------------------------------------------------------------------------%
% Non-vacuity: a non-relation must have a different image, or the equality
% checks above would prove nothing.

:- func non_vacuity_results = list(test_result).

non_vacuity_results = [
    result_of("numeric: sigma_1 sigma_2 differs from sigma_2 sigma_1, t=2",
        ( if max_abs_diff(burau(word(3, [1, 2]), 2.0),
                burau(word(3, [2, 1]), 2.0)) > 0.1 then yes else no )),
    result_of("numeric: sigma_1 differs from identity, t=2",
        ( if max_abs_diff(burau(word(3, [1]), 2.0),
                identity_matrix(3)) > 0.1 then yes else no ))
].

%---------------------------------------------------------------------------%
:- end_module test_braid.
%---------------------------------------------------------------------------%
