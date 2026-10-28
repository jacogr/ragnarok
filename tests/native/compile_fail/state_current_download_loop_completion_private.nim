# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only current dispatcher transitions may retag its borrow or consumed adoption.
# @@Verification={"group": "privacy", "expected": "completion"}
import ../../../src/quic/current_block_download_loop as quic_current_block_download_loop
var dispatcher = default(CurrentDownloadLoop)
discard dispatcher.completion
