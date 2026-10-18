# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of private ownership/results or nominal address/resource domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/pvm/machine
let owner = default(Memory)
discard owner.data
