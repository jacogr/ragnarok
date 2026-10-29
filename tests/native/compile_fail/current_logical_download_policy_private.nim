# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Captured logical policies cannot be replaced through public field mutation.
# @@Verification={"group": "privacy", "expected": "limits"}
import ../../../src/app/current/logical/download as current_logical_download
var owner = default(CurrentLogicalDownloadPolicy)
discard owner.limits
