## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
import ../../../src/codec/[composite, work_digest]
discard CompositeWrite(status: CompositeError.None, byteWritten: 0)
