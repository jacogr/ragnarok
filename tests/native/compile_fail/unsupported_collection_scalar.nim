## Mutable referenced fields have no approved collection scalar codec or ownership contract.
import ../../../src/codec/collections
var input: array[1, byte]
discard decodeVariableSet[string](input, CollectionLimits())
