# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted fixed entropy/time fixtures use separate nominal state and VRF-output domains.
##
## Exposes entropyWords and re-exports state entropy/time domains and EpochSlots for test callers.

import ../../src/codec/state_safrole
from ../../src/codec/header import EpochSlots
export state_safrole, EpochSlots

## Distinct word identities make one-step historical rotation and input ownership observable.
proc entropyWords*(): StateEntropy =
  result = default(StateEntropy)
  for word in 0..<4:
    var bytes = default(array[32, byte])
    for i in 0..<32: bytes[i] = byte(word*32+i) # Every word/position differs without relying on native initialization.
    result[word] = StateEntropyWord(bytes)
