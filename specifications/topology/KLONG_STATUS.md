<!-- SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001 -->
<!-- Copyright (c) 2026 Ahmad Ali Parr. All rights reserved. -->
<!-- Authored by Ahmad Ali Parr. -->
<!-- Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE. -->

# Klong Status

**BLOCKED.** No Klong interpreter or source is installed or reachable here.

- github.com returns HTTP 403 through the session proxy.
- The Klong project is not in the apt archive.
- No alternate download source was found.

Consequences:

- No Klong code has been written, and no Klong result is reported.
- The numerical checks in tests/algebraic are in Mercury, using floats. They are not a
  substitute for Klong. No compatibility layer was invented.
- Native C kernels for matrix multiply, tensor contraction and batched evaluation are
  not implemented in this session. The Phase II native layer is therefore absent, not
  replaced.

To unblock: make a Klong implementation available (source or binary, with its license)
in this environment, then record its version and smoke test here before any Klong
workload is written.
