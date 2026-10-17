## Rejected misuse: retained snapshot and result/variant state remain private.
import ../../../src/codec/[owned, composite]
let value = default(OwnedWorkInfo)
discard value.payloadLength
