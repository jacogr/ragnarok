# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite callback/reception ownership cannot be duplicated.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <BlockDownloadSession>", "build_name": "application-download-session-copy"}
import ../../../src/quic/block_download_session as quic_block_download_session
var original = default(BlockDownloadSession)
var duplicate = original
discard original.busy
discard duplicate.busy
