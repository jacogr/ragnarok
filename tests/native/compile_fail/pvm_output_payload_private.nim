# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for return-output privacy and the nominal byte-copy budget.
## The selected private/read-only field or raw budget must fail compilation.

import ../../../src/pvm/[step, output]
let r = default(OutputResult)
discard r.completed
