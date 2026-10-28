# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A dispatcher cannot duplicate callback addresses or adoption authority.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <BlockDownloadLoop>", "build_name": "application-download-loop-copy"}
import ../../../src/quic/block_download_loop as quic_block_download_loop
var original = default(BlockDownloadLoop)
var duplicate = original
discard original.stage
discard duplicate.stage
