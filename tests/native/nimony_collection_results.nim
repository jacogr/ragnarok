## Failed/default collection and scalar results must reject every value/owner/progress access independently.
import std/[cmdline, syncio]
import ../../src/codec/[collections, natural, fixed_unsigned, bounded]
let useDefault = paramStr(2) == "default"
let limits = CollectionLimits(items: ElementLimit(32), maxBytes: ByteLimit(1024))
var output: seq[byte] = @[]
case paramStr(1)
of "set-owner":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionRead[OwnedSet[
      JamNatural]]]) else: decodeVariableSet[JamNatural]([], limits)
  echo ord(setCount(parsed.value.owner).error)
of "set-consumed":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionRead[OwnedSet[
      JamNatural]]]) else: decodeSet[JamNatural]([], CollectionCount(1), limits)
  echo parsed.value.consumed
of "dictionary-owner":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionRead[OwnedDictionary[JamNatural,
      JamNatural]]]) else: decodeDictionary[JamNatural, JamNatural]([], limits)
  echo ord(dictionaryCount(parsed.value.owner).error)
of "dictionary-consumed":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionRead[OwnedDictionary[JamNatural,
      JamNatural]]]) else: decodeDictionary[JamNatural, JamNatural]([byte(1), 1], limits)
  echo parsed.value.consumed
of "set-count":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionCount]) else: setCount(default(
      OwnedSet[JamNatural]))
  echo uint64(parsed.value)
of "dictionary-count":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionCount]) else: dictionaryCount(
      default(OwnedDictionary[JamNatural, JamNatural]))
  echo uint64(parsed.value)
of "natural":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[JamNatural]) else: setAt(default(OwnedSet[
      JamNatural]), 0)
  echo uint64(parsed.value)
of "unsigned":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionUInt[2]]) else: setAt(default(
      OwnedSet[CollectionUInt[2]]), 0)
  echo uint64(parsed.value.value)
of "bytes":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[CollectionBytes[2]]) else: setAt(default(
      OwnedSet[CollectionBytes[2]]), 0)
  echo parsed.value.bytes[0]
of "pair-key":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[Entry[CollectionBytes[2],
      JamNatural]]) else: dictionaryAt(default(OwnedDictionary[CollectionBytes[2], JamNatural]), 0)
  echo parsed.value.key.bytes[0]
of "pair-value":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[Entry[CollectionBytes[2],
      JamNatural]]) else: dictionaryAt(default(OwnedDictionary[CollectionBytes[2], JamNatural]), 0)
  echo uint64(parsed.value.value)
of "fixed-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeSet([JamNatural(1)],
      CollectionCount(2), limits, output)
  echo parsed.value
of "variable-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeVariableSet([JamNatural(
      1)], limits, output)
  echo parsed.value
of "dictionary-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeDictionary([Entry[
      JamNatural, JamNatural](key: JamNatural(1), value: JamNatural(2))], limits, output)
  echo parsed.value
of "owned-fixed-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeOwnedSet(default(OwnedSet[
      JamNatural]), CollectionCount(0), limits, output)
  echo parsed.value
of "owned-variable-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeOwnedVariableSet(default(
      OwnedSet[JamNatural]), limits, output)
  echo parsed.value
of "owned-dictionary-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeOwnedDictionary(default(
      OwnedDictionary[JamNatural, JamNatural]), limits, output)
  echo parsed.value
of "scalar-natural":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[ScalarRead[JamNatural]]) else: readScalar(
      JamNatural, [])
  echo uint64(parsed.value.value)
of "scalar-natural-consumed":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[ScalarRead[JamNatural]]) else: readScalar(
      JamNatural, [])
  echo parsed.value.consumed
of "scalar-unsigned":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[ScalarRead[CollectionUInt[
      2]]]) else: readScalar(CollectionUInt[2], [])
  echo uint64(parsed.value.value.value)
of "scalar-bytes":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[ScalarRead[CollectionBytes[
      2]]]) else: readScalar(CollectionBytes[2], [])
  echo parsed.value.value.bytes[0]
of "scalar-size":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: scalarSize(CollectionUInt[1](
      value: FixedUnsigned(256)))
  echo parsed.value
of "scalar-natural-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeScalar(JamNatural(1), output)
  echo parsed.value
of "scalar-unsigned-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeScalar(CollectionUInt[1](
      value: FixedUnsigned(256)), output)
  echo parsed.value
of "scalar-bytes-write":
  # A failed/default operation authorizes neither a copied value nor partial ownership/progress.
  let parsed = if useDefault: default(CollectionResult[int]) else: encodeScalar(default(
      CollectionBytes[2]), output)
  echo parsed.value
else:
  # Unknown trusted selectors fail as fixture errors.
  quit(2)
