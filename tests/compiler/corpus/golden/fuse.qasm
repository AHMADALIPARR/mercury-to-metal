# SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
# Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
# Authored by Ahmad Ali Parr.
# Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

OPENQASM 3.0;
include "stdgates.inc";
qubit[2] q;
rz(0.69999999999999996) q[0];
rx(-1) q[1];
cp(1.5707963267948966) q[0], q[1];
