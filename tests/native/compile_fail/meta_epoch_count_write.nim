## Safe code cannot bypass private/read-only header state through validators.
import ../../../src/codec/header
var value = default(EpochMarkerInfo)
value.validators = 0
