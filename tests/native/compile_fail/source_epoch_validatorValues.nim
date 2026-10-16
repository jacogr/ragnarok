## Safe code cannot bypass private/read-only header state through validatorValues.
import ../../../src/codec/header
var value = default(EpochMarker)
discard value.validatorValues
