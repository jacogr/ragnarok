# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive the transport domain only from a nominal configured-genesis header hash.

import ../chain/genesis

func genesisAlpn*(hash: BlockHash): string =
  ## Four leading hash bytes encode exactly eight lowercase nibbles in network byte order.
  const digits = "0123456789abcdef"
  let bytes = array[32, byte](hash)
  result = "jamnp-s/1/"
  for index in 0..<4:
    result.add(digits[int(bytes[index] shr 4)]) # Both nibble indices are bounded by fifteen.
    result.add(digits[int(bytes[index] and 15)])
