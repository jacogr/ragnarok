# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "workerReason"}

## Private worker authority and selected failure payloads cannot be read or forged directly.
import ../../../src/app/block_download as app_block_download
let private = default(BlockDownloadFailure)
discard private.workerReason
