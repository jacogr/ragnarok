## Equal logical numeric domains with different wire widths remain different owner schemas.
import ../../../src/codec/[collections, bounded]
var owner: OwnedSet[CollectionUInt[1]]
var output: array[8, byte]
discard encodeOwnedVariableSet[CollectionUInt[2]](owner, CollectionLimits(), output)
