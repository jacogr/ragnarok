## External callers cannot mutate retained dictionary key/value storage.
import ../../../src/[collections, natural]
var owner: OwnedDictionary[JamNatural, JamNatural]
discard owner.data
