# SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
# Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
# Authored by Ahmad Ali Parr.
# Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

#!/bin/sh
# run_tests.sh -- regression and semantic tests for mercury-qc.
#
# Usage: tests/compiler/run_tests.sh [path/to/mercury_qc]
#
# Checks, in order:
#   1. valid corpus:   check passes; roundtrip passes; -O0 and -O1 emissions
#                      are byte-identical across two runs (determinism).
#   2. golden output:  -O1 emission equals corpus/golden/NAME.qasm.
#   3. invalid corpus: check exits 1 and reports the code named in the
#                      "// expect:" line. Warnings corpus: check exits 0 and
#                      reports the code named in "// expect-warning:".
#   4. semantics:      for each valid unitary circuit, the statevector of -O0
#                      and -O1 agree to 1e-9 per amplitude.
#   5. property sweep: N seeded random unitary circuits, same comparison as 4,
#                      plus roundtrip.
#
# Exit 0 only if every check passes. Output counts each category.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
QC=${1:-$HERE/../../compiler/bin/mercury-qc}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mqc-test.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM

PROP_CASES=${PROP_CASES:-200}
TOL=${TOL:-1e-9}

pass=0
fail=0
fail_list=""

record() {
    # record <ok|bad> <label>
    if [ "$1" = ok ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        fail_list="$fail_list
  FAIL $2"
    fi
}

if [ ! -x "$QC" ]; then
    echo "mercury-qc not found at $QC" >&2
    exit 2
fi

# compare_statevectors A B: exit 0 if amplitudes agree to $TOL.
compare_statevectors() {
    awk -v tol="$TOL" '
        NR == FNR { ar[$1] = $2; ai[$1] = $3; n = FNR; next }
        {
            d1 = ar[$1] - $2; d2 = ai[$1] - $3
            if (d1 < 0) d1 = -d1
            if (d2 < 0) d2 = -d2
            if (d1 > m) m = d1
            if (d2 > m) m = d2
            seen++
        }
        END {
            if (seen != n || n == 0) exit 1
            exit (m <= tol + 0) ? 0 : 1
        }' "$1" "$2"
}

# ---------------------------------------------------------------- 1. valid
for f in "$HERE"/corpus/valid/*.mqc; do
    name=$(basename "$f" .mqc)
    if "$QC" check "$f" >/dev/null 2>&1; then
        record ok "check valid/$name"
    else
        record bad "check valid/$name"
    fi
    if "$QC" roundtrip "$f" >/dev/null 2>&1; then
        record ok "roundtrip valid/$name"
    else
        record bad "roundtrip valid/$name"
    fi
    for opt in -O0 -O1; do
        "$QC" compile "$opt" -o "$TMP/a.qasm" "$f" >/dev/null 2>&1
        "$QC" compile "$opt" -o "$TMP/b.qasm" "$f" >/dev/null 2>&1
        if cmp -s "$TMP/a.qasm" "$TMP/b.qasm"; then
            record ok "deterministic $opt valid/$name"
        else
            record bad "deterministic $opt valid/$name"
        fi
    done
done

# --------------------------------------------------------------- 2. golden
for f in "$HERE"/corpus/valid/*.mqc; do
    name=$(basename "$f" .mqc)
    golden="$HERE/corpus/golden/$name.qasm"
    if [ -f "$golden" ]; then
        "$QC" compile -O1 -o "$TMP/g.qasm" "$f" >/dev/null 2>&1
        if cmp -s "$TMP/g.qasm" "$golden"; then
            record ok "golden $name"
        else
            record bad "golden $name"
        fi
    fi
done

# ------------------------------------------------------------- 3. invalid
for f in "$HERE"/corpus/invalid/*.mqc; do
    name=$(basename "$f" .mqc)
    code=$(sed -n 's,^// expect: \(E-[A-Z-]*\).*,\1,p' "$f" | head -n 1)
    "$QC" check "$f" >/dev/null 2>"$TMP/err.txt"
    rc=$?
    if [ "$rc" -eq 1 ] && grep -q "\[$code\]" "$TMP/err.txt"; then
        record ok "reject invalid/$name ($code)"
    else
        record bad "reject invalid/$name (want $code, rc=$rc)"
    fi
done

# ------------------------------------------------------------ 3b. warnings
# Warnings do not reject a circuit: check exits 0 and prints the code.
for f in "$HERE"/corpus/warnings/*.mqc; do
    name=$(basename "$f" .mqc)
    code=$(sed -n 's,^// expect-warning: \(W-[A-Z-]*\).*,\1,p' "$f" | head -n 1)
    "$QC" check "$f" >/dev/null 2>"$TMP/warn.txt"
    rc=$?
    if [ "$rc" -eq 0 ] && grep -q "\[$code\]" "$TMP/warn.txt"; then
        record ok "warn warnings/$name ($code)"
    else
        record bad "warn warnings/$name (want $code, rc=$rc)"
    fi
done

# ------------------------------------------------------------ 4. semantics
for f in "$HERE"/corpus/valid/*.mqc; do
    name=$(basename "$f" .mqc)
    # Circuits with measurement have no statevector; skip them here.
    if "$QC" statevector "$f" >/dev/null 2>&1; then
        "$QC" statevector "$f" >"$TMP/s0.txt" 2>/dev/null
        # -O1 path: optimize, emit, then evaluate the emitted program.
        "$QC" compile -O1 -o "$TMP/o1.qasm" "$f" >/dev/null 2>&1
        if "$QC" statevector "$TMP/o1.qasm" >"$TMP/s1.txt" 2>/dev/null \
            && compare_statevectors "$TMP/s0.txt" "$TMP/s1.txt"; then
            record ok "semantics valid/$name"
        else
            record bad "semantics valid/$name"
        fi
    fi
done

# ------------------------------------------------------ 5. property sweep
# Random unitary circuits from a seeded generator. Each circuit is compiled
# at -O0 and -O1; the two statevectors must agree, and the emission must
# round-trip.
i=0
while [ "$i" -lt "$PROP_CASES" ]; do
    seed=$((1000 + i))
    awk -v seed="$seed" '
        BEGIN {
            srand(seed)
            nq = 2 + int(rand() * 4)           # 2..5 qubits
            ng = 10 + int(rand() * 40)         # 10..49 gates
            print "qubit[" nq "] q;"
            split("h x y z s sdg t tdg id", one, " ")
            split("rx ry rz", rot, " ")
            for (g = 0; g < ng; g++) {
                r = rand()
                a = int(rand() * nq)
                b = int(rand() * nq)
                if (r < 0.35) {
                    print one[1 + int(rand() * 9)] " q[" a "];"
                } else if (r < 0.55) {
                    print rot[1 + int(rand() * 3)] "(" sprintf("%.17g", (rand() * 6.0) - 3.0) ") q[" a "];"
                } else if (nq >= 2 && r < 0.7) {
                    if (b == a) b = (a + 1) % nq
                    print "cx q[" a "], q[" b "];"
                } else if (nq >= 2 && r < 0.8) {
                    if (b == a) b = (a + 1) % nq
                    print "cz q[" a "], q[" b "];"
                } else if (nq >= 2 && r < 0.88) {
                    if (b == a) b = (a + 1) % nq
                    print "swap q[" a "], q[" b "];"
                } else if (nq >= 2) {
                    if (b == a) b = (a + 1) % nq
                    print "cp(" sprintf("%.17g", (rand() * 6.0) - 3.0) ") q[" a "], q[" b "];"
                }
            }
        }' >"$TMP/p.mqc"
    if "$QC" statevector "$TMP/p.mqc" >"$TMP/p0.txt" 2>/dev/null \
        && "$QC" compile -O1 -o "$TMP/p1.qasm" "$TMP/p.mqc" >/dev/null 2>&1 \
        && "$QC" statevector "$TMP/p1.qasm" >"$TMP/p1.txt" 2>/dev/null \
        && compare_statevectors "$TMP/p0.txt" "$TMP/p1.txt" \
        && "$QC" roundtrip "$TMP/p1.qasm" >/dev/null 2>&1; then
        record ok "property seed=$seed"
    else
        record bad "property seed=$seed"
        cp "$TMP/p.mqc" "$TMP/failed_$seed.mqc" 2>/dev/null
    fi
    i=$((i + 1))
done

echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -ne 0 ]; then
    printf '%s\n' "$fail_list"
    exit 1
fi
exit 0
