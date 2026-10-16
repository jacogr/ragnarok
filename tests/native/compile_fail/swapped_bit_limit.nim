## A bit-count resource ceiling cannot be supplied as a byte budget.
import ../../../src/[bitstrings, bounded]
var input: array[1, byte]
discard decodeBits(input, ByteLimit(8))
