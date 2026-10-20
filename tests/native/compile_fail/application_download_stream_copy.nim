# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native stream callback bindings cannot duplicate handles or partial-write offsets.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <BlockDownloadStream>", "build_name": "application-download-stream-copy"}

import ../../../src/quic/block_download_stream
var original = default(BlockDownloadStream)
var duplicate = original
discard original.active
discard duplicate.active
