## Unsupported fixed scalar widths cannot instantiate a collection codec.
import ../../../src/codec/collections
var input: array[1, byte] = default(array[1, byte])
discard decodeVariableSet[CollectionUInt[-1]](input, CollectionLimits())
