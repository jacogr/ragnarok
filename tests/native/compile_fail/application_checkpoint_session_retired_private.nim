# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Session lifecycle and receipt alternatives remain private.
# @@Verification={"group": "privacy", "expected": "retired"}
import ../../../src/app/checkpoint/session as checkpoint_session
let session = default(ApplicationCheckpointSession)
discard session.retired
