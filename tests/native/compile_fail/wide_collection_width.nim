## Unsupported fixed scalar widths cannot instantiate a collection codec.
import ../../../src/codec/collections
var input: array[1, byte]
discard decodeVariableSet[CollectionUInt[9]](input, CollectionLimits())
