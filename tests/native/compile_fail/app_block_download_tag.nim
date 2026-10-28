# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default result alternatives cannot be retagged as successful admission.
# @@Verification={"group": "privacy", "expected": "successful"}

import ../../../src/app/block_download as app_block_download
var outcome = default(BlockDownloadResult[BlockDownloadId])
outcome.successful = true
