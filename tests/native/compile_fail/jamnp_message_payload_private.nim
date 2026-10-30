# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Failure/default results cannot reveal unchecked payload or progress through raw fields.
import "../../../src/jamnp-s/messages"
let result = default(MessageResult[int])
discard result.completed
