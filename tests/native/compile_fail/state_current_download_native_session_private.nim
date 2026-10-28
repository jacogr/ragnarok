# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native callbacks and their exact retained current receiver remain private.
# @@Verification={"group": "privacy", "expected": "download"}
import ../../../src/quic/current_block_download_session as quic_current_block_download_session
var owner = default(CurrentDownloadSession)
discard owner.download
