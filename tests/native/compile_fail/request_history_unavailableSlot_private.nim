# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw request shape/payload storage is private behind selected-field accessors.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "unavailableSlot"}

import ../../../src/codec/state_requests
let history = default(RequestHistory)
discard history.unavailableSlot
