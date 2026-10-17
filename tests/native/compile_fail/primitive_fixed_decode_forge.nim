## Rejected misuse: primitive result state is private and exposed only through read-only accessors.
import ../../../src/codec/[natural, fixed_unsigned]
discard FixedDecodeResult(success: true, decodedValue: FixedUnsigned(0), byteConsumed: 0)
