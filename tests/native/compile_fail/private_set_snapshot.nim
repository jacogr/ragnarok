## External callers cannot mutate retained set scalar storage.
import ../../../src/codec/[collections, natural]
var owner: OwnedSet[JamNatural]
discard owner.data
