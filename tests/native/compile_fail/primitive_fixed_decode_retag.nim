## Rejected misuse: primitive result state is private and exposed only through read-only accessors.
import ../../../src/codec/[natural, fixed_unsigned]
var value = default(FixedDecodeResult)
value.success = true
