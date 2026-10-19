# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of private ownership/results or nominal address/resource domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "failedPage"}

import ../../../src/pvm/machine
let outcome = default(MachineResult[Memory])
discard outcome.failedPage
