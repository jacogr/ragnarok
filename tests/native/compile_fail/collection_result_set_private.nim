## Callers cannot bypass private/read-only collection result state.
import ../../../src/codec/[collections, natural]
var value = default(CollectionResult[CollectionRead[OwnedSet[JamNatural]]])
discard value.completed
