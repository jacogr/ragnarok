# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The failure reason has no mutable public field.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "error"}

import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.error = BsError.None
