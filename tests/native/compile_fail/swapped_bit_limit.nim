# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bit-count resource ceiling cannot be supplied as a byte budget.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[bitstrings, bounded]
var input: array[1, byte] = default(array[1, byte])
discard decodeBits(input, ByteLimit(8))
