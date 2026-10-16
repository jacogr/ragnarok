## Safe code cannot bypass private/read-only header state through entropy.
import ../../../src/codec/header
var value = default(EpochMarkerInfo)
value.entropy = EpochEntropy(default(array[32, byte]))
