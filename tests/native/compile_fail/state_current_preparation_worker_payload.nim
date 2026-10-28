# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native current results remain private until the matching completion accessor is guarded.
# @@Verification={"group": "privacy", "expected": "currentPrepared"}

import ../../../src/app/preparation_worker as app_preparation_worker
let completion = default(PreparationCompletion)
discard completion.currentPrepared
