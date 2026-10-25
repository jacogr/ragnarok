# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Failed/default protocol results cannot expose an unguarded successful payload.
import ../../../src/state/fuzz_session
let outcome = default(FuzzSessionResult[FuzzDispatch])
discard outcome.completed
