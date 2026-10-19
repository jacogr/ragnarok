# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Advertised preimage lengths cannot substitute for absolute history timeslots.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "RequestSlot"}

import ../../../src/codec/state_requests
let history = availableHistory(RequestLength(1))
discard history
