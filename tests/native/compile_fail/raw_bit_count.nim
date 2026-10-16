## Byte extents cannot implicitly become schema bit counts.
import ../../../src/codec/bitstrings
var input: array[1, byte] = default(array[1, byte])
discard decodeFixedBits(input, 8'u64, BitLimit(8))
