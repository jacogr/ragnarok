## Rejected misuse: retained snapshot and result/variant state remain private.
import ../../../src/codec/[owned, composite]
discard OwnedWorkInfo(outputKind: WorkKind.Success, payloadLength: 0)
