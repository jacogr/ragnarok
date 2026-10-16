## Remaining migration gate: the natural codec still exposes raw variant fields.
import ../../src/codec/natural
import std/syncio
# This must reject once primitive results receive the guarded API; until then the gate stays red.
let decoded = decode(newSeq[byte](0))
echo uint64(decoded.value)
