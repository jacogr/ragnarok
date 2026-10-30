# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native callbacks and their exact retained current receiver remain private.
# @@Verification={"group": "privacy", "expected": "download"}
import "../../../src/jamnp-s/current/block/download/session" as current_block_download_session
var owner = default(CurrentDownloadSession)
discard owner.download
