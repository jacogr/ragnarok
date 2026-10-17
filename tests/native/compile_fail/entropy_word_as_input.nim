## Stored entropy and newly supplied VRF output belong to distinct nominal domains.
import ../../../src/state/entropy
import ../../../src/codec/state_safrole
from ../../../src/codec/header import EpochSlots
discard advanceEntropyTime(default(StateEntropy), StateTime(0), StateTime(1),
    default(StateEntropyWord), EpochSlots(12))
