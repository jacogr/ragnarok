## Raw host counts cannot implicitly authorize a fixed collection cardinality.
import ../../../src/[collections, natural]
var input: array[1, byte]
discard decodeSet[JamNatural](input, 1'u64, CollectionLimits())
