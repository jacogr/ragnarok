## Rejected misuse: retained snapshot and result/variant state remain private.
import ../../../src/codec/[owned, composite]
var value = default(OwnedOptionalInfo)
value.isPresent = true
