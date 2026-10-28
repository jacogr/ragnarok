# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Array-to-sequence construction cannot bypass the native callback owner's copy prohibition.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <BlockDownloadStream>", "build_name": "application-download-stream-array-copy"}

import ../../../src/quic/block_download_stream as quic_block_download_stream
var original = default(BlockDownloadStream)
var duplicates = @[original]
discard original.active # The original binding remains live after sequence construction.
discard duplicates[0].active
