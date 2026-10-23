# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge retained logical startup authority.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/app/[current_logical_startup, current_logical_download]
var owner = default(CurrentLogicalStartupResult[CurrentLogicalDownloadPolicy])
discard owner.completed
