# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical dispatcher source/result ownership cannot bypass explicit configure, adoption or rearm gates.
# @@Verification={"group": "privacy", "expected": "logicalPolicy"}
import "../../../src/quic/current/block/download/loop" as current_block_download_loop
var owner = default(CurrentDownloadLoop)
discard owner.logicalPolicy
