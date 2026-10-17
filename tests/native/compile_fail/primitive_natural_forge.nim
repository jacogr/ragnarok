## Rejected misuse: primitive result state is private and exposed only through read-only accessors.
import ../../../src/codec/[natural, fixed_unsigned]
discard DecodeResult(success: true, decodedValue: JamNatural(0), byteConsumed: 1)
