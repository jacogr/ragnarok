# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal fetch(0) offsets construct independent valid parameter inputs for economic consumers.
import ../../src/chain/parameters
proc economicTestWire*(base = 100'u64, item = 2'u64, octet = 3'u64): array[ParameterBytes, byte] =
  ## Encode three E8 rates plus the existing minimum population/clock validity fields without production profile capture.
  result = default(array[ParameterBytes, byte])
  for index in 0..<8:
    result[index] = byte((item shr (8*index)) and 255)
    result[8+index] = byte((octet shr (8*index)) and 255)
    result[16+index] = byte((base shr (8*index)) and 255) # Fetch tuple order is item, byte, account.
  result[24] = 2
  result[30] = 12
  result[80] = 6
  result[84] = 4
