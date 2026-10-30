# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local peer IDs cannot stand in for expected Ed25519 authentication keys.
# @@Verification={"group": "nominal", "expected": "DownloadPeerKey", "early": ["openPeer", "[3] expected: DownloadPeerKey but got: DownloadPeerId"]}
import "../../../src/jamnp-s/block/download/peers" as block_download_peers
import ../../../src/app/download/schedule as download_schedule
var catalog = default(BlockDownloadPeers)
discard catalog.openPeer(DownloadPeerId(1), DownloadPeerId(2), 1, "", "", "")
