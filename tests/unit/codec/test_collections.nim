# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Focused collection lifetime, copy independence, strict policy, zero-width and source alias
## regressions.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "collection_arc_release"}

import ../../support/arc_evidence
import std/[assertions, syncio]
import ../../../src/codec/[collections, natural, fixed_unsigned, bounded]

# Select complete success before reading metadata, scalars or retained handles.
proc checked[T](parsed: CollectionResult[T]): T =
  assert parsed.error == CollectionError.None
  parsed.value

let limits = CollectionLimits(items: ElementLimit(32), maxBytes: ByteLimit(1024))
var input = @[2'u8, 0xFF, 0, 0, 1]
var owner = checked(decodeVariableSet[CollectionUInt[2]](input, limits)).owner
let retained = owner
owner = OwnedSet[CollectionUInt[2]]()
# The retained typed snapshot ignores mutations to every original input byte.
for i in 0..<input.len: input[i] = 0
var copied = checked(setAt(retained, 0))
assert uint64(copied.value) == 255
copied.value = FixedUnsigned(7)
assert uint64(checked(setAt(retained, 0)).value) == 255
assert uint64(checked(setAt(retained, 1)).value) == 256
var output: array[128, byte] = default(array[128, byte])
# Numeric 255<256 must succeed despite ff00 sorting after 0001 as raw octets.
assert checked(encodeOwnedVariableSet(retained, limits, output)) == 5
assert output[0] == 2 and output[1] == 255 and output[2] == 0 and output[3] == 0 and output[4] == 1
var strict = limits
strict.items = ElementLimit(1)
# New caller resource policy applies to retained owners before destination capacity or writes.
for i in 0..<output.len: output[i] = 0xA5
assert encodeOwnedVariableSet(retained, strict, output).error == CollectionError.LimitExceeded
strict = limits; strict.maxBytes = ByteLimit(4)
assert encodeOwnedVariableSet(retained, strict, output).error == CollectionError.LimitExceeded
assert encodeOwnedSet(retained, CollectionCount(1), limits, output).error ==
    CollectionError.InvalidCount
# Failed source and policy checks cannot modify any destination byte.
for octet in output: assert octet == 0xA5
let dictionary = checked(decodeDictionary[CollectionBytes[2], JamNatural](@[2'u8, 0, 255, 9, 1, 0,
    3], limits)).owner
var pair = checked(dictionaryAt(dictionary, 0))
pair.key.bytes[0] = 255; pair.value = JamNatural(0)
assert checked(dictionaryAt(dictionary, 0)).key.bytes[0] == 0
assert uint64(checked(dictionaryAt(dictionary, 0)).value) == 9
# Dictionary values may descend or repeat; only keys determine canonical order.
assert checked(encodeOwnedDictionary(dictionary, limits, output)) == 7
var absentSet: OwnedSet[JamNatural] = default(OwnedSet[JamNatural])
var absentDictionary: OwnedDictionary[JamNatural, JamNatural] = default(OwnedDictionary[JamNatural, JamNatural])
assert setCount(absentSet).error == CollectionError.InvalidOwner
assert setAt(absentSet, 0).error == CollectionError.InvalidOwner
assert dictionaryCount(absentDictionary).error == CollectionError.InvalidOwner
assert dictionaryAt(absentDictionary, 0).error == CollectionError.InvalidOwner
assert encodeOwnedVariableSet(absentSet, limits, output).error == CollectionError.InvalidOwner
assert encodeOwnedSet(absentSet, CollectionCount(0), limits, output).error ==
    CollectionError.InvalidOwner
assert encodeOwnedDictionary(absentDictionary, limits, output).error ==
    CollectionError.InvalidOwner
var empty: seq[byte] = default(seq[byte])
let singleton = checked(decodeSet[CollectionUInt[0]](empty, CollectionCount(1), limits)).owner
assert uint64(checked(setCount(singleton))) == 1
assert checked(encodeOwnedSet(singleton, CollectionCount(1), limits, empty)) == 0
assert decodeVariableSet[CollectionUInt[0]](@[2'u8], limits).error == CollectionError.NonCanonical
let zeroDict = checked(decodeDictionary[CollectionUInt[0], CollectionBytes[0]](@[1'u8], limits)).owner
assert uint64(checked(dictionaryCount(zeroDict))) == 1
assert decodeDictionary[CollectionUInt[0], CollectionBytes[0]](@[2'u8], limits).error ==
    CollectionError.NonCanonical
# Borrowed numeric source storage must not overlap any earlier discriminator or later destination element.
var sources = [JamNatural(1), JamNatural(2)]
let sourceBytes = cast[ptr array[sizeof(sources), byte]](addr sources[0])
assert encodeVariableSet(sources, limits, sourceBytes[].toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
assert uint64(sources[0]) == 1 and uint64(sources[1]) == 2
# The entire destination must be checked even when its prefix would hit only a later source element.
assert encodeVariableSet(sources, limits, sourceBytes[].toOpenArray(7, 9)).error ==
    CollectionError.AliasedBuffers
assert uint64(sources[0]) == 1 and uint64(sources[1]) == 2
var pairs = [Entry[JamNatural, JamNatural](key: JamNatural(1), value: JamNatural(3))]
let pairBytes = cast[ptr array[sizeof(pairs), byte]](addr pairs[0])
assert encodeDictionary(pairs, limits, pairBytes[].toOpenArray(0, 2)).error ==
    CollectionError.AliasedBuffers
assert uint64(pairs[0].key) == 1 and uint64(pairs[0].value) == 3
# A destination inside the associated value must be rejected before the count or key is written.
assert encodeDictionary(pairs, limits, pairBytes[].toOpenArray(8, 10)).error ==
    CollectionError.AliasedBuffers
assert uint64(pairs[0].key) == 1 and uint64(pairs[0].value) == 3

# Checked scalar helpers reject late width overflow and short destinations without changing output.
for i in 0..<output.len: output[i] = 0xA5
assert encodeScalar(CollectionUInt[1](value: FixedUnsigned(256)), output).error ==
    CollectionError.ValueOutOfRange
assert encodeScalar(JamNatural(128), empty).error == CollectionError.OutputTooSmall
for octet in output: assert octet == 0xA5 # Scalar preflight preserves the entire destination too.
var scalarBytes = CollectionBytes[2](bytes: [byte(1), 2])
let scalarAlias = cast[ptr array[sizeof(scalarBytes), byte]](addr scalarBytes)
# Scalar writers snapshot a fixed value before committing, so direct source/output overlap is well-defined.
assert checked(encodeScalar(scalarBytes, scalarAlias[].toOpenArray(0, 1))) == 2
assert scalarBytes.bytes == [byte(1), 2]
var shifted = [CollectionBytes[2](bytes: [byte(1), 2]), default(CollectionBytes[2])]
let shiftedBytes = cast[ptr array[sizeof(shifted), byte]](addr shifted[0])
# Shifting output into a later source octet proves the scalar writer copies before its first commit.
assert checked(encodeScalar(shifted[0], shiftedBytes[].toOpenArray(1, 2))) == 2
assert shiftedBytes[][1] == 1 and shiftedBytes[][2] == 2
assert sizeof(CollectionBytes[0]) > 0 # Zero wire extent still has real typed sequence storage.

# Escaping local source buffers must leave independent value-only collection snapshots.
proc escapedSet(): OwnedSet[JamNatural] =
  var bytes = @[2'u8, 1, 2]
  result = checked(decodeVariableSet[JamNatural](bytes, limits)).owner
  for i in 0..<bytes.len: bytes[i] = 0 # Returned ownership severs the original buffer lifetime.

# Replaced set/dictionary handles, zero-width domains and copied records must all release on scope exit.
proc releaseCycle() =
  var set = escapedSet()
  let oldSet = set
  set = checked(decodeVariableSet[JamNatural]([byte(2), 3, 4], limits)).owner
  assert uint64(checked(setAt(set, 0))) == 3
  set = default(OwnedSet[JamNatural])
  assert uint64(checked(setAt(oldSet, 0))) == 1
  var bytes = @[2'u8, 0, 255, 9, 1, 0, 3]
  var dict = checked(decodeDictionary[CollectionBytes[2], JamNatural](bytes, limits)).owner
  let oldDict = dict
  dict = checked(decodeDictionary[CollectionBytes[2], JamNatural]([byte(1), 0, 1, 7], limits)).owner
  dict = default(OwnedDictionary[CollectionBytes[2], JamNatural])
  bytes = @[]
  var copy = checked(dictionaryAt(oldDict, 0))
  copy.key.bytes[0] = 255
  copy.value = JamNatural(0)
  assert checked(dictionaryAt(oldDict, 0)).key.bytes == [byte(0), 255]
  assert uint64(checked(dictionaryAt(oldDict, 0)).value) == 9
  var output = newSeq[byte](16)
  assert checked(encodeOwnedDictionary(oldDict, limits, output)) == 7
  let zero = checked(decodeVariableSet[CollectionBytes[0]]([byte(1)], limits)).owner
  assert uint64(checked(setCount(zero))) == 1
  assert checked(encodeOwnedSet(zero, CollectionCount(1), limits, output)) == 0
  let zeroPairs = checked(decodeDictionary[CollectionUInt[0], CollectionBytes[0]]([byte(1)], limits)).owner
  assert uint64(checked(dictionaryCount(zeroPairs))) == 1

# Warm public allocator paths before measuring live occupancy with outer fixtures retained.
for i in 0..<100: releaseCycle()
let beforeRelease = getOccupiedMem()
# Every isolated scope must drop its final retained set, dictionary, zero-width snapshot and copied values.
for i in 0..<1000: releaseCycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve numeric observations outside the platform-independent success marker.
recordArcRelease("collections", 1000, beforeRelease, afterRelease)
echo "COLLECTION_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony collections: retained value snapshots, strict policy, aliases and checked scalar writes passed"
