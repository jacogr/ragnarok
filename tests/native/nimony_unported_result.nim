## Remaining migration gate: composite results still expose raw variant progress.
import ../../src/codec/[composite, bounded]
import std/syncio
# Primitive results are protected; this composite result must receive the same guarded API next.
let decoded = decodeOptionalBorrowed(newSeq[byte](0), ByteLimit(1))
echo decoded.consumed
