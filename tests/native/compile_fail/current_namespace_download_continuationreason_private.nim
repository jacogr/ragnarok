# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "continuationReason"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/current/logical/download as current_logical_download
let source = default(CurrentLogicalDownloadResult)
discard source.continuationReason
