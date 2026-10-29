# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Joined session internals cannot be forged or retagged.
# @@Verification={"group": "privacy", "expected": "generation"}
import "../../../src/quic/block/download/session" as block_download_session
var owner = DownloadSessionAttempt()
discard owner.generation
