# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "payload"}

## Callers cannot forge success or mutate retained parser/batch storage.
import "../../../src/jamnp-s/messages"
let reader = default(MessageReader)
discard reader.payload
