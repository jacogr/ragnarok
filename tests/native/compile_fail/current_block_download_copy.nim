# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The current receiver independently rejects duplication of its mutable input and worker borrow.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CurrentBlockDownload>", "build_name": "current-block-download-copy"}
import ../../../src/app/current_block_download
var original = default(CurrentBlockDownload)
var duplicate = original
discard original.cancel(default(CurrentBlockDownloadId))
discard duplicate.cancel(default(CurrentBlockDownloadId))
