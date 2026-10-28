# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "continuation"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/current_logical_download as app_current_logical_download
let source = default(CurrentLogicalDownloadPolicy)
discard source.continuation
