# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <AncestorPeer>", "build_name": "application-ancestor-peer-copy"}

## Composite native transport owners must reject duplication during actual lowering.
import "../../../src/jamnp-s/ancestor/peer" as ancestor_peer
var original = default(AncestorPeer)
var duplicate = original
discard original.stage
discard duplicate.stage
