# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct success-payload extraction cannot bypass the guarded result accessor.
# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/app/block_download
var outcome = default(BlockDownloadResult[BlockDownloadId])
discard outcome.completed
