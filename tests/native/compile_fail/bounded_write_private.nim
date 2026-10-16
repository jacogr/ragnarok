## Rejected misuse: bounded result state is private and its public reason is read-only.
import ../../../src/codec/bounded
let value = default(WriteResult)
discard value.byteWritten
