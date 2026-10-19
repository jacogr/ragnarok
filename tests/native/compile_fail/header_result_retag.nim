# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private/read-only header state through status.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/codec/header
var value = default(HeaderResult[int])
value.status = HeaderError.None
