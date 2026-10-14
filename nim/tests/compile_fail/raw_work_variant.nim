## Deliberately invalid: service fields, work variants and record-count policies are nominal types.
import ../../src/[composite, bounded]
let value = 1'u8
var output: array[1, byte]
discard encodeWorkBorrowed(value, [], ByteLimit(0), output)
