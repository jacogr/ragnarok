# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only current dispatcher transitions may retag its borrow or consumed adoption.
# @@Verification={"group": "privacy", "expected": "owner"}
import "../../../src/jamnp-s/current/block/download/loop" as current_block_download_loop
var dispatcher = default(CurrentDownloadLoop)
discard dispatcher.owner
