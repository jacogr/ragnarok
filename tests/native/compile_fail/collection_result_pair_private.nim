## Callers cannot bypass private/read-only collection result state.
import ../../../src/codec/[collections, natural]
var value = default(CollectionResult[Entry[CollectionBytes[2], JamNatural]])
discard value.completed
