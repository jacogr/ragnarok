## Safe code cannot bypass private/read-only header state through validatorCount.
import ../../../src/codec/header
var value = default(EpochMarkerInfo)
discard value.validatorCount
