# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw request shape/payload storage is private behind selected-field accessors.
import ../../../src/codec/state_requests
let history = default(RequestHistory)
discard history.sinceSlot
