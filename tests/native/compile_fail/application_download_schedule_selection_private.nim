# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scheduling authority remains private.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/app/download_schedule
var owner = default(DownloadSelection)
discard owner.status
