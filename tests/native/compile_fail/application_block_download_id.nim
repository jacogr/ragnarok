# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A raw-block reception generation cannot stand in for a stream-download generation.
# @@Verification={"group": "nominal", "expected": "BlockDownloadId", "early": ["cancel", "[2] expected: BlockDownloadId but got: BlockInputId"]}

import "../../../src/app/block/download" as block_download
import "../../../src/app/block/input" as block_input
var download = default(BlockDownload)
discard download.cancel(default(BlockInputId))
