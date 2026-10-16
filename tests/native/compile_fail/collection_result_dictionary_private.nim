## Callers cannot bypass private/read-only collection result state.
import ../../../src/codec/[collections, natural]
var value = default(CollectionResult[CollectionRead[OwnedDictionary[JamNatural, JamNatural]]])
discard value.completed
