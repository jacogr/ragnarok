# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Construct a new valid shape rather than retagging or writing guarded fields.
import ../../../src/codec/state_requests
var history = default(RequestHistory)
history.unavailableFrom = RequestSlot(0)
