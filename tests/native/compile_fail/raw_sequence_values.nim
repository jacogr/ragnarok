## Deliberately invalid: bounded limits and fixed-element values require their own domain types.
import ../../../src/codec/[bounded, fixed_unsigned]
let values = [1'u64]
var output: array[10, byte]
discard encodeSequence(values, ByteWidth(1), ElementLimit(1), output)
