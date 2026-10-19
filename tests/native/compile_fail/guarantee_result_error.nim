# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private guarantee state through error.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "error"}

import ../../../src/codec/guarantees
var value = default(GuaranteeResult[int])
value.error = GuaranteeError.None
