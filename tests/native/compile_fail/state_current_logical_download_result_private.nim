# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical success extraction cannot bypass its guarded immutable result accessor.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/app/current_logical_download as app_current_logical_download
var owner = default(CurrentLogicalDownloadResult)
discard owner.completed
