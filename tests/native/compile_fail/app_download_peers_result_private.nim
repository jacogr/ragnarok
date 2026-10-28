# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native peer ownership and selected result tags remain private.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/quic/block_download_peers as quic_block_download_peers
var owner = default(DownloadPeerResult[bool])
discard owner.status
