# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Byte extents cannot implicitly become schema bit counts.
import ../../../src/codec/bitstrings
var input: array[1, byte] = default(array[1, byte])
discard decodeFixedBits(input, 8'u64, BitLimit(8))
