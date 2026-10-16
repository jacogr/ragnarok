## External callers cannot mutate retained dictionary key/value storage.
import ../../../src/codec/[collections, natural]
var owner: OwnedDictionary[JamNatural, JamNatural]
discard owner.data
