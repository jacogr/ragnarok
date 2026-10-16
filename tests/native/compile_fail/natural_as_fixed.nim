## Deliberately invalid: a raw value/width or general natural is not the required fixed domain type.
import ../../../src/codec/fixed_unsigned
import ../../../src/codec/natural
let value = JamNatural(1)
discard encodeFixed(value, ByteWidth(1))
