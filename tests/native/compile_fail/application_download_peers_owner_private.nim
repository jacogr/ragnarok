# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native peer ownership and selected result tags remain private.
# @@Verification={"group": "privacy", "expected": "slots"}
import "../../../src/jamnp-s/block/download/peers" as block_download_peers
var owner = default(BlockDownloadPeers)
discard owner.slots
