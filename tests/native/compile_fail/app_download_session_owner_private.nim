# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Joined session internals cannot be forged or retagged.
# @@Verification={"group": "privacy", "expected": "route"}
import ../../../src/quic/block_download_session as quic_block_download_session
var owner = default(BlockDownloadSession)
discard owner.route
