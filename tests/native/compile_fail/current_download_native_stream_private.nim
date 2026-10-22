# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native callbacks and their exact retained current receiver remain private.
# @@Verification={"group": "privacy", "expected": "handle"}
import ../../../src/quic/current_block_download_stream
var owner = default(CurrentDownloadStream)
discard owner.handle
