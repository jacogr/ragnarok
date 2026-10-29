# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Composed owner storage, result payloads and discriminators remain private.

import ../../../src/state/accumulation/consensus as accumulation_consensus
var owner: PreparedAccumulationConsensus
discard owner.data
