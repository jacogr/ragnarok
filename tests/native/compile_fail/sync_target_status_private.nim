# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External producers cannot forge an author-ready target observation.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/quic/sync_targets
var observation = default(SyncTargetProgress)
observation.status = CurrentSyncStage.CaughtUp
