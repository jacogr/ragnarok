## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
import ../../../src/codec/[composite, work_digest]
let value = default(OptionalBlob)
discard value.payloadSpan
