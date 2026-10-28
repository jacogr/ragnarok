# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller cannot replace the exclusively borrowed Services pointer.
# @@Verification={"group": "privacy", "expected": "owner"}
import ../../../src/quic/block_download_loop as quic_block_download_loop
var dispatcher = default(BlockDownloadLoop)
discard dispatcher.owner
