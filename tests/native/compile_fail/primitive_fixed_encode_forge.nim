## Rejected misuse: primitive result state is private and exposed only through read-only accessors.
import ../../../src/codec/[natural, fixed_unsigned]
discard FixedEncodeResult(success: true, encodedValue: EncodedFixed(len: 0))
