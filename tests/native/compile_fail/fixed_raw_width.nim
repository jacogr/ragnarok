## Deliberately invalid: a raw value/width or general natural is not the required fixed domain type.
import ../../../src/fixed_unsigned
let raw = 1
discard encodeFixed(FixedUnsigned(1), raw)
