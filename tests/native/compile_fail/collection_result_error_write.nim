## Callers cannot bypass private/read-only collection result state.
import ../../../src/codec/[collections, natural]
var value = default(CollectionResult[int])
value.error = CollectionError.None
