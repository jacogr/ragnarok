# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The current native composite independently rejects duplicated callback and lease ownership.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CurrentDownloadStream>", "build_name": "current-download-native-stream-copy"}
import "../../../src/quic/current/block/download/stream" as current_block_download_stream
var original = default(CurrentDownloadStream)
var duplicate = original
discard original.active
discard duplicate.active
