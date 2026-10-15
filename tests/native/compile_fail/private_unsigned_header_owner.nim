## Intentional rejection keeps immutable header/marker snapshot storage private.
import ../../../src/header

var owner: OwnedUnsignedHeader
discard owner.data
