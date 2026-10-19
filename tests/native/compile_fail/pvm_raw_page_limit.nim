# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of private ownership/results or nominal address/resource domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "[2] expected: PageLimit but got: uint32", "early": ["captureMemory(", "[2] expected: PageLimit but got: uint32"]}

import ../../../src/pvm/machine
discard captureMemory([], 1'u32)
