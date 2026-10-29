# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scheduling authority remains private.
# @@Verification={"group": "privacy", "expected": "owner"}
import ../../../src/app/download/schedule as download_schedule
var owner = default(DownloadAttempt)
discard owner.owner
