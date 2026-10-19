# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Construct a new valid shape rather than retagging or writing guarded fields.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "availableFrom"}

import ../../../src/codec/state_requests
var history = default(RequestHistory)
history.availableFrom = RequestSlot(0)
