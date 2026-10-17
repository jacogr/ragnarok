## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
import ../../../src/codec/[composite, work_digest]
discard OptionalBlob(isPresent: true, payloadSpan: BlobSpan())
