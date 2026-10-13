## Deliberately invalid: a raw value/width or general natural is not the required fixed domain type.
import ../../src/fixed_unsigned
import ../../src/natural
let value = JamNatural(1)
discard encodeFixed(value, ByteWidth(1))
