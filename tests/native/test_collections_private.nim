## Project-only white-box alias checks; external compile probes separately enforce private snapshot storage.
include ../../src/collections

# Private fixture storage setup requires a completely validated owner.
proc checked[T](parsed: CollectionResult[T]): T =
  doAssert parsed.error == CollectionError.None
  parsed.value

let limits = CollectionLimits(items: ElementLimit(8), maxBytes: ByteLimit(128))
let set = checked(decodeVariableSet[JamNatural](@[2'u8, 1, 2], limits)).owner
let bytes = cast[ptr UncheckedArray[byte]](addr set.data.values[0])
doAssert encodeOwnedVariableSet(set, limits, bytes.toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
doAssert encodeOwnedSet(set, CollectionCount(2), limits, bytes.toOpenArray(0, 1)).error ==
    CollectionError.AliasedBuffers
let dictionary = checked(decodeDictionary[JamNatural, JamNatural](@[1'u8, 1, 9], limits)).owner
let pairBytes = cast[ptr UncheckedArray[byte]](addr dictionary.data.values[0])
doAssert encodeOwnedDictionary(dictionary, limits, pairBytes.toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
doAssert uint64(checked(setAt(set, 1))) == 2
doAssert uint64(checked(dictionaryAt(dictionary, 0)).value) == 9
echo "Nim collections: immutable private typed-storage aliases passed"
