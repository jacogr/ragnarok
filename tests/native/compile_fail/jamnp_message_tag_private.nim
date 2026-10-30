# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Callers cannot forge a successful message result by retagging a default failure.
import "../../../src/jamnp-s/messages"
var result = default(MessageResult[int])
result.status = MessageError.None
