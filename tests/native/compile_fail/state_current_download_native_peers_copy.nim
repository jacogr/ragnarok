# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The current native composite independently rejects duplicated callback and lease ownership.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CurrentDownloadPeers>", "build_name": "current-download-native-peers-copy"}
import ../../../src/quic/current_block_download_peers as quic_current_block_download_peers
var original = default(CurrentDownloadPeers)
var duplicate = original
discard original.count
discard duplicate.count
