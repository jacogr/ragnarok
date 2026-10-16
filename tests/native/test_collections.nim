## Focused collection lifetime, copy independence, strict policy, zero-width and source alias regressions.
import ../../src/codec/[collections, natural, fixed_unsigned, bounded]

# Select complete success before reading metadata, scalars or retained handles.
proc checked[T](parsed: CollectionResult[T]): T =
  doAssert parsed.error == CollectionError.None
  parsed.value

let limits = CollectionLimits(items: ElementLimit(32), maxBytes: ByteLimit(1024))
var input = @[2'u8, 0xFF, 0, 0, 1]
var owner = checked(decodeVariableSet[CollectionUInt[2]](input, limits)).owner
let retained = owner
owner = OwnedSet[CollectionUInt[2]]()
# The retained typed snapshot ignores mutations to every original input byte.
for i in 0..<input.len: input[i] = 0
var copied = checked(setAt(retained, 0))
doAssert uint64(copied.value) == 255
copied.value = FixedUnsigned(7)
doAssert uint64(checked(setAt(retained, 0)).value) == 255
doAssert uint64(checked(setAt(retained, 1)).value) == 256
var output: array[128, byte]
# Numeric 255<256 must succeed despite ff00 sorting after 0001 as raw octets.
doAssert checked(encodeOwnedVariableSet(retained, limits, output)) == 5
doAssert output[0..4] == @[2'u8, 255, 0, 0, 1]
var strict = limits
strict.items = ElementLimit(1)
# New caller resource policy applies to retained owners before destination capacity or writes.
for i in 0..<output.len: output[i] = 0xA5
doAssert encodeOwnedVariableSet(retained, strict, output).error == CollectionError.LimitExceeded
strict = limits; strict.maxBytes = ByteLimit(4)
doAssert encodeOwnedVariableSet(retained, strict, output).error == CollectionError.LimitExceeded
doAssert encodeOwnedSet(retained, CollectionCount(1), limits, output).error ==
    CollectionError.InvalidCount
# Failed source and policy checks cannot modify any destination byte.
for octet in output: doAssert octet == 0xA5
let dictionary = checked(decodeDictionary[CollectionBytes[2], JamNatural](@[2'u8, 0, 255, 9, 1, 0,
    3], limits)).owner
var pair = checked(dictionaryAt(dictionary, 0))
pair.key.bytes[0] = 255; pair.value = JamNatural(0)
doAssert checked(dictionaryAt(dictionary, 0)).key.bytes[0] == 0
doAssert uint64(checked(dictionaryAt(dictionary, 0)).value) == 9
# Dictionary values may descend or repeat; only keys determine canonical order.
doAssert checked(encodeOwnedDictionary(dictionary, limits, output)) == 7
var absentSet: OwnedSet[JamNatural]
var absentDictionary: OwnedDictionary[JamNatural, JamNatural]
doAssert setCount(absentSet).error == CollectionError.InvalidOwner
doAssert setAt(absentSet, 0).error == CollectionError.InvalidOwner
doAssert dictionaryCount(absentDictionary).error == CollectionError.InvalidOwner
doAssert dictionaryAt(absentDictionary, 0).error == CollectionError.InvalidOwner
doAssert encodeOwnedVariableSet(absentSet, limits, output).error == CollectionError.InvalidOwner
doAssert encodeOwnedSet(absentSet, CollectionCount(0), limits, output).error ==
    CollectionError.InvalidOwner
doAssert encodeOwnedDictionary(absentDictionary, limits, output).error ==
    CollectionError.InvalidOwner
var empty: seq[byte]
let singleton = checked(decodeSet[CollectionUInt[0]](empty, CollectionCount(1), limits)).owner
doAssert uint64(checked(setCount(singleton))) == 1
doAssert checked(encodeOwnedSet(singleton, CollectionCount(1), limits, empty)) == 0
doAssert decodeVariableSet[CollectionUInt[0]](@[2'u8], limits).error == CollectionError.NonCanonical
let zeroDict = checked(decodeDictionary[CollectionUInt[0], CollectionBytes[0]](@[1'u8], limits)).owner
doAssert uint64(checked(dictionaryCount(zeroDict))) == 1
doAssert decodeDictionary[CollectionUInt[0], CollectionBytes[0]](@[2'u8], limits).error ==
    CollectionError.NonCanonical
# Borrowed numeric source storage must not overlap any earlier discriminator or later destination element.
var sources = [JamNatural(1), JamNatural(2)]
let sourceBytes = cast[ptr UncheckedArray[byte]](addr sources[0])
doAssert encodeVariableSet(sources, limits, sourceBytes.toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
doAssert uint64(sources[0]) == 1 and uint64(sources[1]) == 2
# The entire destination must be checked even when its prefix would hit only a later source element.
doAssert encodeVariableSet(sources, limits, sourceBytes.toOpenArray(7, 9)).error ==
    CollectionError.AliasedBuffers
doAssert uint64(sources[0]) == 1 and uint64(sources[1]) == 2
var pairs = [Entry[JamNatural, JamNatural](key: JamNatural(1), value: JamNatural(3))]
let pairBytes = cast[ptr UncheckedArray[byte]](addr pairs[0])
doAssert encodeDictionary(pairs, limits, pairBytes.toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
doAssert uint64(pairs[0].key) == 1 and uint64(pairs[0].value) == 3
# A destination inside the associated value must be rejected before the count or key is written.
doAssert encodeDictionary(pairs, limits, pairBytes.toOpenArray(8, 10)).error ==
    CollectionError.AliasedBuffers
doAssert uint64(pairs[0].key) == 1 and uint64(pairs[0].value) == 3
var guarded = false
try:
  # Default results may not expose a fabricated owner or consumed cursor.
  var missing: CollectionResult[CollectionRead[OwnedSet[JamNatural]]]
  discard missing.value.consumed
except FieldDefect:
  # All selected-alternative runtime guards remain enabled in checked optimized builds.
  guarded = true
doAssert guarded
guarded = false
try:
  # A rejected noncanonical collection likewise cannot publish a partial owner or cursor.
  discard decodeVariableSet[JamNatural](@[2'u8, 1, 1], limits).value.consumed
except FieldDefect:
  # Rejection must retain the same enabled variant guard as uninitialized results.
  guarded = true
doAssert guarded
echo "Nim collections: retained value snapshots, strict policy, aliases and selected-result guards passed"
