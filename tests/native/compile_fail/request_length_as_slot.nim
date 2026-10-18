# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Advertised preimage lengths cannot substitute for absolute history timeslots.
import ../../../src/codec/state_requests
let history = availableHistory(RequestLength(1))
discard history
