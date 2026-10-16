## Trial-only negative executable: a failed decoder must not expose success-only coordinates.
import ../../src/codec/bounded
import std/syncio
# The empty payload has no natural header, so this production decoder returns Truncated.
let decoded = decodeBytesBorrowed(newSeq[byte](0), ByteLimit(1))
# This deliberately invalid caller must fail under the required variant-field safety contract.
echo decoded.length
