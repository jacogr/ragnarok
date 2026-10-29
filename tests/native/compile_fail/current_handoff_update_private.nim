# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "update"}

## Producers cannot substitute arbitrary queued owners by writing handoff fields.
import ../../../src/app/current/handoff as current_handoff
let handoff = default(CurrentAccumulationHandoff)
discard handoff.update
