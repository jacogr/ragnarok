## Rejected misuse: retained snapshot and result/variant state remain private.
import ../../../src/codec/[owned, composite]
discard OwnedOptionalInfo(isPresent: true, payloadLength: 0)
