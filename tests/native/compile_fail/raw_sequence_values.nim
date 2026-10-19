# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: bounded limits and fixed-element values require their own domain types.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "[1] expected: openArray but got: array[0..0, uint64]", "early": ["encodeSequence(", "[1] expected: openArray but got: array[0..0, uint64]"]}

import ../../../src/codec/[bounded, fixed_unsigned]
let values = [1'u64]
var output = default(array[10, byte])
discard encodeSequence(values, ByteWidth(1), ElementLimit(1), output)
