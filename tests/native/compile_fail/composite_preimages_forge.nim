## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
import ../../../src/codec/[composite, work_digest]
discard PreimageResult(status: CompositeError.None, elementCount: 0, byteConsumed: 1)
