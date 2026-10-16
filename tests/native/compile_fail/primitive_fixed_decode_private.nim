## Rejected misuse: primitive result state is private and exposed only through read-only accessors.
import ../../../src/codec/[natural, fixed_unsigned]
let value = default(FixedDecodeResult)
discard value.decodedValue
