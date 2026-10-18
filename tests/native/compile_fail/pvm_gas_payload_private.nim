# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged gas results or untyped simulation boundaries.
import ../../../src/pvm/[program, gas]
let r = default(GasResult)
discard r.completed
