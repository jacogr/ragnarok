# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only white-box alias checks; external compile probes separately enforce private snapshot storage.
import std/[assertions, syncio]
include ../../../src/codec/collections

# Private fixture storage setup requires a completely validated owner.
proc checked[T](parsed: CollectionResult[T]): T =
  assert parsed.error == CollectionError.None
  parsed.value

let limits = CollectionLimits(items: ElementLimit(8), maxBytes: ByteLimit(128))
let set = checked(decodeVariableSet[JamNatural](@[2'u8, 1, 2], limits)).owner
let setData = set.data
assert setData != nil
let bytes = cast[ptr array[2*sizeof(JamNatural), byte]](addr setData.values[0])
assert encodeOwnedVariableSet(set, limits, bytes[].toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
assert encodeOwnedSet(set, CollectionCount(2), limits, bytes[].toOpenArray(0, 1)).error ==
    CollectionError.AliasedBuffers
let dictionary = checked(decodeDictionary[JamNatural, JamNatural](@[1'u8, 1, 9], limits)).owner
let dictData = dictionary.data
assert dictData != nil
let pairBytes = cast[ptr array[sizeof(Entry[JamNatural, JamNatural]), byte]](addr dictData.values[0])
assert encodeOwnedDictionary(dictionary, limits, pairBytes[].toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
assert uint64(checked(setAt(set, 1))) == 2
assert uint64(checked(dictionaryAt(dictionary, 0)).value) == 9
echo "Nim collections: immutable private typed-storage aliases passed"
