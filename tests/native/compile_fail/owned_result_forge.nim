## Rejected misuse: retained snapshot and result/variant state remain private.
import ../../../src/codec/[owned, composite]
discard OwnedResult[int](status: OwnershipError.None, completed: 0)
