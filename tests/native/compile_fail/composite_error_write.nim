## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
import ../../../src/codec/[composite, work_digest]
var value = default(CompositeWrite)
value.error = CompositeError.None
