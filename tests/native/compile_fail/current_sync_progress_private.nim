# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External producers cannot forge a ready observation through its private discriminator.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/quic/current/sync as current_sync
var observation = default(CurrentSyncProgress)
observation.status = CurrentSyncStage.CaughtUp
