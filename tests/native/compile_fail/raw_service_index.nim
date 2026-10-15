## Deliberately invalid: service fields, work variants and record-count policies are nominal types.
import ../../../src/[composite, bounded]
let service = 1'u32
let record = Preimage(service: service, blob: BlobSpan())
discard record
