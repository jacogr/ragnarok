## A dictionary owner cannot stand in for a set, even with identical scalar key types.
import ../../../src/[collections, natural]
var owner: OwnedDictionary[JamNatural, JamNatural]
discard setCount(owner)
