# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "expected"}

## Private peer authority/lifetime fields cannot be forged outside checked operations.
import ../../../src/quic/ancestor_peer as quic_ancestor_peer
let owner = default(AncestorPeer)
discard owner.expected
