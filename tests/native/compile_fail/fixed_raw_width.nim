# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: a raw value/width or general natural is not the required fixed domain
## type.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: ByteWidth but got: int64", "early": ["encodeFixed(", "[2] expected: ByteWidth but got: int64"]}

import ../../../src/codec/fixed_unsigned
let raw = 1
discard encodeFixed(FixedUnsigned(1), raw)
