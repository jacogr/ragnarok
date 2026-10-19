# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stored entropy and newly supplied VRF output belong to distinct nominal domains.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "StateEntropyWord", "early": ["advanceEntropyTime(", "[4] expected: EntropyInput but got: StateEntropyWord"]}

import ../../../src/state/entropy
import ../../../src/codec/state_safrole
from ../../../src/codec/header import EpochSlots
discard advanceEntropyTime(default(StateEntropy), StateTime(0), StateTime(1),
    default(StateEntropyWord), EpochSlots(12))
