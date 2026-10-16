## External callers cannot mutate retained set scalar storage.
import ../../../src/[collections, natural]
var owner: OwnedSet[JamNatural]
discard owner.data
