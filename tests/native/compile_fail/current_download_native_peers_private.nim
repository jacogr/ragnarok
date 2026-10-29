# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native callbacks and their exact retained current receiver remain private.
# @@Verification={"group": "privacy", "expected": "slots"}
import "../../../src/quic/current/block/download/peers" as current_block_download_peers
var owner = default(CurrentDownloadPeers)
discard owner.slots
