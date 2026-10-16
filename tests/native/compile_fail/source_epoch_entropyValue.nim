## Safe code cannot bypass private/read-only header state through entropyValue.
import ../../../src/codec/header
var value = default(EpochMarker)
discard value.entropyValue
