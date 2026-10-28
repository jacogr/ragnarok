# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A session callback token cannot acknowledge a detached scheduler lease.
# @@Verification={"group": "nominal", "expected": "DownloadAttempt", "early": ["finish", "[2] expected: DownloadAttempt but got: ref DownloadSessionAttempt.Obj not nil"]}
import ../../../src/quic/block_download_session as quic_block_download_session
import ../../../src/app/download_schedule as app_download_schedule
var schedule = default(DownloadSchedule)
let token = DownloadSessionAttempt()
discard schedule.finish(token, DownloadAttemptOutcome.Retry, DownloadScheduleTick(0))
