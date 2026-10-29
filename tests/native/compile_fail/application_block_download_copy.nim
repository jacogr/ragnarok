# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The composite download owns mutable context/bytes even when its nested input already rejects copying.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <BlockDownload>", "build_name": "application-block-download-copy"}

import "../../../src/app/block/download" as block_download
var original = default(BlockDownload)
var duplicate = original
discard original.cancel(default(BlockDownloadId))
discard duplicate.cancel(default(BlockDownloadId))
