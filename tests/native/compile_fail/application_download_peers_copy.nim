# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A catalog cannot duplicate outgoing engines or stable callback contexts.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <BlockDownloadPeers>", "build_name": "application-download-peers-copy"}
import "../../../src/quic/block/download/peers" as block_download_peers
var original = default(BlockDownloadPeers)
var duplicate = original
discard original.count
discard duplicate.count
