## Intentional rejection protects a nominal header field or sealed/unsigned ownership boundary.
import ../../../src/codec/[header]

var value: UnsignedHeader
value.entropyProof = HeaderSeal(default(array[96, byte]))
