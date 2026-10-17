## A bit-count resource ceiling cannot be supplied as a byte budget.
import ../../../src/codec/[bitstrings, bounded]
var input: array[1, byte] = default(array[1, byte])
discard decodeBits(input, ByteLimit(8))
