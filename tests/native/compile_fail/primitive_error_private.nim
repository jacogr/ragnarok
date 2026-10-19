# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: primitive result state is private and exposed only through read-only
## accessors.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "failureReason"}

import ../../../src/codec/[natural, fixed_unsigned]
let value = default(FixedDecodeResult)
discard value.failureReason
