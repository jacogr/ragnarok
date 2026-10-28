# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed worker and acknowledgement ownership rejects actual implicit ARC duplication.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <ApplicationCheckpointSession>", "build_name": "application-checkpoint-session-copy"}
import ../../../src/app/checkpoint_session as app_checkpoint_session
var original = default(ApplicationCheckpointSession)
var duplicate = original
original.close()
duplicate.close()
