# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Byte extents cannot implicitly become schema bit counts.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "[2] expected: BitCount but got: uint64"}

import ../../../src/codec/bitstrings as codec_bitstrings
var input: array[1, byte] = default(array[1, byte])
discard decodeFixedBits(input, 8'u64, BitLimit(8))
