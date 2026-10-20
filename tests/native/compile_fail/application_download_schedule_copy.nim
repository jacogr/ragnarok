# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable scheduling plans cannot duplicate an outstanding attempt.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <DownloadSchedule>", "build_name": "application-download-schedule-copy"}
import ../../../src/app/download_schedule
var original = default(DownloadSchedule)
var duplicate = original
discard original.busy
discard duplicate.busy
