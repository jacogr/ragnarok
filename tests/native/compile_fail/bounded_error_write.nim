## Rejected misuse: bounded result state is private and its public reason is read-only.
import ../../../src/codec/bounded
var value = default(BlobResult)
value.error = ContainerError.None
