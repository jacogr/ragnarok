# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Candidate storage remains private on every default, failed and successful schedule result.
import ../../../src/state/sealer_schedule
var hidden = default(SealerScheduleResult)
discard hidden.completed
