# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for host-response gas and action domains.
## Raw integers and guest exit reasons cannot stand in for explicit typed host replies.

## Verification: {"group": "nominal", "expected": "got: uint64 but wanted: MachineGas"}

import ../../../src/pvm/[machine, step]
discard HostResponse(gas: 1'u64)
