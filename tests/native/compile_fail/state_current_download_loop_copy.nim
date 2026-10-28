# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current dispatchers cannot duplicate callback addresses, Services borrows or result consumption authority.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CurrentDownloadLoop>", "build_name": "current-download-loop-copy"}
import ../../../src/quic/current_block_download_loop as quic_current_block_download_loop
var original = default(CurrentDownloadLoop)
var duplicate = original
discard original.stage
discard duplicate.stage
