# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The current native composite independently rejects duplicated callback and lease ownership.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CurrentDownloadSession>", "build_name": "current-download-native-session-copy"}
import ../../../src/quic/current_block_download_session
var original = default(CurrentDownloadSession)
var duplicate = original
discard original.busy
discard duplicate.busy
