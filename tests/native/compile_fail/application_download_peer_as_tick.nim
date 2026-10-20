# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Session identity is not a monotonic clock observation.
# @@Verification={"group": "nominal", "expected": "DownloadScheduleTick", "early": ["select", "[2] expected: DownloadScheduleTick but got: DownloadPeerId"]}
import ../../../src/app/download_schedule
var schedule = default(DownloadSchedule)
discard schedule.select(DownloadPeerId(1))
