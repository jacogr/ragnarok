# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted independent field adapter for context/import/commitment/item/package codecs.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/parseutils
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/codec/work_digest as codec_work_digest
import ../../src/codec/composite as codec_composite
import ../../src/codec/bounded as codec_bounded

# Test-only success selection checks the failure branch before accessing expected-good getter fields.
proc checked[T](parsed: PackageResult[T]): T =
  assert parsed.error == PackageError.None
  parsed.value

# Decode bounded public fixture hex without exposing any real application input parser.
proc unhex(text: string): seq[byte] {.raises.} =
  if text == "-": return @[] # Preserve an empty byte field as one trusted protocol token.
  assert text.len mod 2 == 0 and text.len <= 64*1024*1024
  result = newSeq[byte](text.len div 2)
  # Each pair constructs mutable bytes owned solely by this adapter request.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Invalid trusted text cannot be accepted as a different byte sequence.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

# Observe complete public identity/payload encodings without a production encode round trip.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Whitespace transport requires a token for zero bytes.
  result = ""
  # Every observed octet contributes exactly two lowercase hexadecimal characters.
  for value in bytes: result.add(toHex(int(value), 2).toLowerAscii())

# Parse all unsigned fixture values without narrowing through signed host integers.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

# Fixed typed encoder sources are built directly from explicit trusted identity tokens.
proc fixed[N: static[int]](text: string): array[N, byte] {.raises.} =
  result = default(array[N, byte])
  let bytes = unhex(text)
  assert bytes.len == N
  # No production decoder creates an encoding source field.
  for i in 0..<N: result[i] = bytes[i]

# Consume one trusted source-field token without assigning meaning to its future wire width.
proc take(parts: seq[string], cursor: var int): string =
  result = parts[cursor]
  inc cursor

# Construct an independently named context source, including declared count failures beyond its fixed array.
proc contextSource(parts: seq[string], cursor: var int): RefinementContext {.raises.} =
  result = default(RefinementContext)
  result.anchor = BlockHash(bytes: fixed[32](take(parts, cursor)))
  result.anchorSlot = AnchorSlot(unsigned(take(parts, cursor)))
  result.stateRoot = StateRoot(bytes: fixed[32](take(parts, cursor)))
  result.accumulationRoot = AccumulationRoot(bytes: fixed[32](take(parts, cursor)))
  result.lookupAnchor = BlockHash(bytes: fixed[32](take(parts, cursor)))
  result.lookupSlot = LookupSlot(unsigned(take(parts, cursor)))
  result.lookupStateRoot = LookupStateRoot(bytes: fixed[32](take(parts, cursor)))
  result.prerequisiteCount = parseInt(take(parts, cursor))
  assert result.prerequisiteCount in 0..9
  # Consume the invalid ninth identity too, without indexing the production fixed eight-slot array.
  for i in 0..<result.prerequisiteCount:
    let key = PackageHash(bytes: fixed[32](take(parts, cursor)))
    if i < 8: result.prerequisites[i] = key # Preflight must reject the declared ninth prerequisite.

# Construct a typed import alternative from explicit kind/identity/index fields.
proc importSource(parts: seq[string], cursor: var int): ImportReference {.raises.} =
  let kind = parseInt(take(parts, cursor))
  let key = fixed[32](take(parts, cursor))
  let index = parseInt(take(parts, cursor))
  assert kind in 0..1 and index in 0..65535
  if kind == 0:
    result = rootImport(SegmentRoot(bytes: key), ImportIndex(index)) # Direct root.
  else:
    result = packageImport(PackageHash(bytes: key), ImportIndex(index)) # Package dependency.

# Construct a fixed advertised input commitment without resolving its preimage.
proc commitmentSource(parts: seq[string], cursor: var int): ExtrinsicCommitment {.raises.} =
  result = default(ExtrinsicCommitment)
  result.hash = ExtrinsicHash(fixed[32](take(parts, cursor)))
  result.length = ExtrinsicLength(unsigned(take(parts, cursor)))

# Build all item sources independently, including deliberately invalid last manifest entries.
proc itemSource(parts: seq[string], cursor: var int): WorkItem {.raises.} =
  result = default(WorkItem)
  result.service = ServiceIndex(unsigned(take(parts, cursor)))
  result.codeHash = CodeHash(fixed[32](take(parts, cursor)))
  result.refineGas = Gas(unsigned(take(parts, cursor)))
  result.accumulateGas = Gas(unsigned(take(parts, cursor)))
  result.exports = ExportCount(unsigned(take(parts, cursor)))
  result.payload = unhex(take(parts, cursor))
  let imports = parseInt(take(parts, cursor))
  assert imports in 0..3073
  result.imports = newSeq[ImportReference](imports)
  # Every source reference is explicit; sequence order and duplicates are preserved by construction.
  for i in 0..<imports: result.imports[i] = importSource(parts, cursor)
  let extrinsics = parseInt(take(parts, cursor))
  assert extrinsics in 0..129
  result.extrinsics = newSeq[ExtrinsicCommitment](extrinsics)
  # Fixed commitments are independent typed sources rather than a decoded manifest slice.
  for i in 0..<extrinsics: result.extrinsics[i] = commitmentSource(parts, cursor)

# Build complete package sources without any production package or child decoder.
proc packageSource(parts: seq[string], cursor: var int): WorkPackage {.raises.} =
  result = default(WorkPackage)
  result.host = AuthorizerHost(unsigned(take(parts, cursor)))
  result.codeHash = CodeHash(fixed[32](take(parts, cursor)))
  result.context = contextSource(parts, cursor)
  result.authorization = unhex(take(parts, cursor))
  result.configuration = unhex(take(parts, cursor))
  let count = parseInt(take(parts, cursor))
  assert count in 0..17
  result.items = newSeq[WorkItem](count)
  # Late malformed items must be observed by encoder preflight before writing the package prefix.
  for i in 0..<count: result.items[i] = itemSource(parts, cursor)

# Observe each fixed context field rather than comparing only output from the same encoder and decoder.
proc fields(value: RefinementContext): string =
  result = hex(value.anchor.bytes) & " " & $uint32(value.anchorSlot) & " " & hex(
      value.stateRoot.bytes) &
    " " & hex(value.accumulationRoot.bytes) & " " & hex(value.lookupAnchor.bytes) & " " & $uint32(
        value.lookupSlot) &
    " " & hex(value.lookupStateRoot.bytes) & " " & $value.prerequisiteCount
  # The active canonical prerequisite count selects complete owned hash copies.
  for i in 0..<value.prerequisiteCount: result.add(" " & hex(value.prerequisites[i].bytes))

# Observe the selected nominal identity domain and the lower fifteen-bit index separately.
proc fields(value: ImportReference): string =
  case value.kind
  of ImportKind.Root:
    result = "0 " & hex(value.root.bytes) # No package lookup selector survives as an index bit.
  of ImportKind.Package:
    result = "1 " & hex(value.package.bytes) # The high bit selects a package identity.
  result.add(" " & $uint16(value.index))

# Observe every fixed input commitment byte and its full E4 advertised length.
proc fields(value: ExtrinsicCommitment): string =
  hex(array[32, byte](value.hash)) & " " & $uint32(value.length)

# Observe every item field through owner-bound metadata/copy/getter APIs, including copied-value immutability.
proc fields(owner: OwnedWorkItem): string =
  var info = checked(workItemInfo(owner))
  var payload = newSeq[byte](info.payloadBytes+3)
  # All extraction destinations retain extra sentinels outside the selected bytes.
  for i in 0..<payload.len: payload[i] = 0xA5
  assert checked(copyItemPayload(owner, payload)) == info.payloadBytes
  for i in info.payloadBytes..<payload.len: assert payload[i] == 0xA5 # No unused suffix writes.
  result = $uint32(info.service) & " " & hex(array[32, byte](info.codeHash)) & " " & $uint64(
      info.refineGas) & " " &
    $uint64(info.accumulateGas) & " " & $uint64(info.exports) & " " & hex(payload.toOpenArray(0,
        info.payloadBytes-1)) & " " & $info.imports
  let gas = info.refineGas
  info.refineGas = Gas(0)
  assert uint64(checked(workItemInfo(owner)).refineGas) == uint64(gas)
  assert importAt(owner, -1).error == PackageError.InvalidIndex
  assert importAt(owner, info.imports).error == PackageError.InvalidIndex
  # Imports retain sequence duplicates and both nominal identity alternatives.
  for i in 0..<info.imports:
    var reference = checked(importAt(owner, i))
    result.add(" " & fields(reference))
    let index = reference.index
    reference.index = ImportIndex(0)
    assert uint16(checked(importAt(owner, i)).index) == uint16(index)
  result.add(" " & $info.extrinsics)
  assert extrinsicAt(owner, -1).error == PackageError.InvalidIndex
  assert extrinsicAt(owner, info.extrinsics).error == PackageError.InvalidIndex
  # A locally mutated commitment must never alter immutable parent storage.
  for i in 0..<info.extrinsics:
    var commitment = checked(extrinsicAt(owner, i))
    result.add(" " & fields(commitment))
    let length = commitment.length
    commitment.length = ExtrinsicLength(0)
    assert uint32(checked(extrinsicAt(owner, i)).length) == uint32(length)

# Observe package blobs and child metadata through retained owners without exporting mutable snapshot storage.
proc fields(owner: OwnedWorkPackage): string =
  var info = checked(workPackageInfo(owner))
  result = $uint32(info.host) & " " & hex(array[32, byte](info.codeHash)) & " " & fields(info.context)
  # Selecting a named blob prevents detached offset extraction from the wrong parent buffer.
  for field in [PackageBlob.Authorization, PackageBlob.Configuration]:
    let length = if field == PackageBlob.Authorization: info.authorizationBytes else: info.configurationBytes # The two metadata roles stay separate.
    var output = newSeq[byte](length+3)
    for i in 0..<output.len: output[i] = 0xA5 # Observe untouched suffix capacity for empty/nonempty blobs.
    assert checked(copyPackageBlob(owner, field, output)) == length
    for i in length..<output.len: assert output[i] == 0xA5 # Only selected owner-bound bytes were copied.
    result.add(" " & hex(output.toOpenArray(0, length-1)))
  result.add(" " & $info.items)
  assert workItemAt(owner, -1).error == PackageError.InvalidIndex
  assert workItemAt(owner, info.items).error == PackageError.InvalidIndex
  # Child handles retain the same immutable parent and expose no standalone spans.
  for i in 0..<info.items: result.add(" " & fields(checked(workItemAt(owner, i))))
  let slot = info.context.anchorSlot
  info.context.anchorSlot = AnchorSlot(0)
  assert uint32(checked(workPackageInfo(owner)).context.anchorSlot) == uint32(slot)

# Encode explicit fields and assert unchanged entire outputs on failure or untouched suffixes on success.
proc encodeRequest(parts: seq[string], config: PackageConfig) {.raises.} =
  let capacity = parseInt(parts[5])
  assert capacity in 0..33554432
  var output = newSeq[byte](capacity)
  # Every failure must leave the whole caller buffer unchanged, even for a late source error.
  for i in 0..<capacity: output[i] = 0xA5
  var cursor = 6
  var encoded: PackageResult[int] = default(PackageResult[int])
  case parts[1]
  of "C": encoded = encodeRefinementContext(contextSource(parts, cursor),
      output) # Independently constructed context.
  of "R": encoded = encodeImportReference(importSource(parts, cursor),
      output) # Explicit packed-bit source alternative.
  of "X": encoded = encodeExtrinsicCommitment(commitmentSource(parts, cursor), output) # Full E4 length source.
  of "I": encoded = encodeWorkItem(itemSource(parts, cursor), config, output) # Complete nested item source.
  of "P": encoded = encodeWorkPackage(packageSource(parts, cursor), config,
      output) # Complete independent package source.
  else: assert false # The trusted protocol defines no other codec family.
  assert cursor == parts.len
  if encoded.error != PackageError.None:
    # Even complete earlier records may not write a prefix before a late source rejection.
    for octet in output: assert octet == 0xA5
    echo ($encoded.error).toLowerAscii()
  else:
    # Success writes exactly the selected wire prefix and leaves excess capacity untouched.
    for i in encoded.value..<output.len: assert output[i] == 0xA5
    echo hex(output.toOpenArray(0, encoded.value-1))

# Decode then independently observe fields; original input mutation must not affect owned success values.
proc decodeRequest(parts: seq[string], config: PackageConfig) {.raises.} =
  var input = unhex(parts[5])
  # Each fixed API keeps concrete result fields visible to Nimony overload resolution.
  case parts[1]
  of "C":
    # Complete fixed context and canonical prerequisite set.
    let parsed = decodeRefinementContext(input)
    if parsed.error != PackageError.None:
      echo ($parsed.error).toLowerAscii() # Failure exposes no default record or progress.
    else:
      # Copied fixed fields must survive mutation of the entire caller input.
      for octet in input.mitems: octet = 0
      let completed = parsed.value
      echo $completed.consumed & " " & fields(completed.value)
  of "R":
    # Both nominal import alternatives with the packed E2 selector.
    let parsed = decodeImportReference(input)
    if parsed.error != PackageError.None:
      echo ($parsed.error).toLowerAscii() # Failure exposes no default record or progress.
    else:
      # Copied fixed fields must survive mutation of the entire caller input.
      for octet in input.mitems: octet = 0
      let completed = parsed.value
      echo $completed.consumed & " " & fields(completed.value)
  of "X":
    # Exact fixed commitment identity and full E4 length.
    let parsed = decodeExtrinsicCommitment(input)
    if parsed.error != PackageError.None:
      echo ($parsed.error).toLowerAscii() # Failure exposes no default record or progress.
    else:
      # Copied fixed fields must survive mutation of the entire caller input.
      for octet in input.mitems: octet = 0
      let completed = parsed.value
      echo $completed.consumed & " " & fields(completed.value)
  of "I":
    let parsed = decodeWorkItem(input, config)
    if parsed.error != PackageError.None:
      echo ($parsed.error).toLowerAscii() # Failed scans contain no partial item owner.
    else:
      let consumed = parsed.value.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      for i in 0..<input.len: input[i] = 0 # Immutable captured bytes outlive caller storage contents.
      let observed = fields(parsed.value.owner)
      var output = newSeq[byte](consumed)
      assert checked(encodeOwnedWorkItem(parsed.value.owner, output)) == consumed
      assert hex(output) == original
      echo $consumed & " " & observed
  of "P":
    let parsed = decodeWorkPackage(input, config)
    if parsed.error != PackageError.None:
      echo ($parsed.error).toLowerAscii() # A late item failure cannot retain any partial package owner.
    else:
      let consumed = parsed.value.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      for i in 0..<input.len: input[i] = 0 # Include unrelated trailing input in mutation.
      let observed = fields(parsed.value.owner)
      var output = newSeq[byte](consumed)
      assert checked(encodeOwnedWorkPackage(parsed.value.owner, output)) == consumed
      assert hex(output) == original
      echo $consumed & " " & observed
  else: assert false # Trusted fixtures never request an undefined family.

# Batched requests own all fixture allocations and retain no cross-request mutable state.
try:
  # File reading is confined to the trusted adapter, never production protocol decoding.
  for line in readFile(paramStr(1)).splitLines():
    if line.len > 0:
      # Blank lines contain no operation; requests carry explicit gas and storage ceilings.
      let parts = line.splitWhitespace()
      assert parts.len >= 6
      let config = PackageConfig(refineGas: Gas(unsigned(parts[2])),
        accumulateGas: Gas(unsigned(parts[3])), maxBytes: ByteLimit(unsigned(parts[4])))
      if parts[0] == "E": encodeRequest(parts, config) # Independent named source fields.
      else: decodeRequest(parts, config) # Exact wire decoding and field observation.
except:
  # Missing files or malformed trusted text must fail rather than silently omit coverage.
  quit 2
