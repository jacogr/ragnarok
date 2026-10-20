# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw bytes cannot substitute for a decoded immutable block owner.
# @@Verification={"group":"nominal","expected":"OwnedBlock","early":["prepareCandidate(","[2] expected: OwnedBlock but got: array"]}

import ../../../src/app/[candidate, chain]
discard prepareCandidate(default(ApplicationChain), [0'u8], [], default(ApplicationCandidateLimits))
