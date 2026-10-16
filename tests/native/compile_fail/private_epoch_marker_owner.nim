## Intentional rejection keeps immutable header/marker snapshot storage private.
import ../../../src/codec/header

var owner: OwnedEpochMarker
discard owner.data
