## Trusted independent field adapter for context/import/commitment/item/package codecs.
import std/[os, strutils]
import ../../src/codec/[work_package, work_report, work_digest, composite, bounded]

# Test-only success selection checks the failure branch before accessing expected-good getter fields.
proc checked[T](parsed: PackageResult[T]): T =
  doAssert parsed.error == PackageError.None
  parsed.value

# Decode bounded public fixture hex without exposing any real application input parser.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Preserve an empty byte field as one trusted protocol token.
  doAssert text.len mod 2 == 0 and text.len <= 64*1024*1024
  result = newSeq[byte](text.len div 2)
  # Each pair constructs mutable bytes owned solely by this adapter request.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Observe complete public identity/payload encodings without a production encode round trip.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Whitespace transport requires a token for zero bytes.
  # Every observed octet contributes exactly two lowercase hexadecimal characters.
  for value in bytes: result.add(toHex(value, 2).toLowerAscii())

# Fixed typed encoder sources are built directly from explicit trusted identity tokens.
proc fixed[N: static int](text: string): array[N, byte] =
  let bytes = unhex(text)
  doAssert bytes.len == N
  # No production decoder creates an encoding source field.
  for i in 0..<N: result[i] = bytes[i]

# Consume one trusted source-field token without assigning meaning to its future wire width.
proc take(parts: seq[string], cursor: var int): string =
  result = parts[cursor]
  inc cursor

# Construct an independently named context source, including declared count failures beyond its fixed array.
proc contextSource(parts: seq[string], cursor: var int): RefinementContext =
  result.anchor = BlockHash(bytes: fixed[32](take(parts, cursor)))
  result.anchorSlot = AnchorSlot(parseBiggestUInt(take(parts, cursor)))
  result.stateRoot = StateRoot(bytes: fixed[32](take(parts, cursor)))
  result.accumulationRoot = AccumulationRoot(bytes: fixed[32](take(parts, cursor)))
  result.lookupAnchor = BlockHash(bytes: fixed[32](take(parts, cursor)))
  result.lookupSlot = LookupSlot(parseBiggestUInt(take(parts, cursor)))
  result.lookupStateRoot = LookupStateRoot(bytes: fixed[32](take(parts, cursor)))
  result.prerequisiteCount = parseInt(take(parts, cursor))
  doAssert result.prerequisiteCount in 0..9
  # Consume the invalid ninth identity too, without indexing the production fixed eight-slot array.
  for i in 0..<result.prerequisiteCount:
    let key = PackageHash(bytes: fixed[32](take(parts, cursor)))
    if i < 8: result.prerequisites[i] = key # Preflight must reject the declared ninth prerequisite.

# Construct a typed import alternative from explicit kind/identity/index fields.
proc importSource(parts: seq[string], cursor: var int): ImportReference =
  let kind = parseInt(take(parts, cursor))
  let key = fixed[32](take(parts, cursor))
  let index = parseInt(take(parts, cursor))
  doAssert kind in 0..1 and index in 0..65535
  if kind == 0:
    result = ImportReference(kind: ImportKind.Root, root: SegmentRoot(bytes: key),
        index: ImportIndex(index)) # Direct root.
  else:
    result = ImportReference(kind: ImportKind.Package, package: PackageHash(bytes: key),
        index: ImportIndex(index)) # Package dependency.

# Construct a fixed advertised input commitment without resolving its preimage.
proc commitmentSource(parts: seq[string], cursor: var int): ExtrinsicCommitment =
  result.hash = ExtrinsicHash(fixed[32](take(parts, cursor)))
  result.length = ExtrinsicLength(parseBiggestUInt(take(parts, cursor)))

# Build all item sources independently, including deliberately invalid last manifest entries.
proc itemSource(parts: seq[string], cursor: var int): WorkItem =
  result.service = ServiceIndex(parseBiggestUInt(take(parts, cursor)))
  result.codeHash = CodeHash(fixed[32](take(parts, cursor)))
  result.refineGas = Gas(parseBiggestUInt(take(parts, cursor)))
  result.accumulateGas = Gas(parseBiggestUInt(take(parts, cursor)))
  result.exports = ExportCount(parseBiggestUInt(take(parts, cursor)))
  result.payload = unhex(take(parts, cursor))
  let imports = parseInt(take(parts, cursor))
  doAssert imports in 0..3073
  result.imports = newSeq[ImportReference](imports)
  # Every source reference is explicit; sequence order and duplicates are preserved by construction.
  for i in 0..<imports: result.imports[i] = importSource(parts, cursor)
  let extrinsics = parseInt(take(parts, cursor))
  doAssert extrinsics in 0..129
  result.extrinsics = newSeq[ExtrinsicCommitment](extrinsics)
  # Fixed commitments are independent typed sources rather than a decoded manifest slice.
  for i in 0..<extrinsics: result.extrinsics[i] = commitmentSource(parts, cursor)

# Build complete package sources without any production package or child decoder.
proc packageSource(parts: seq[string], cursor: var int): WorkPackage =
  result.host = AuthorizerHost(parseBiggestUInt(take(parts, cursor)))
  result.codeHash = CodeHash(fixed[32](take(parts, cursor)))
  result.context = contextSource(parts, cursor)
  result.authorization = unhex(take(parts, cursor))
  result.configuration = unhex(take(parts, cursor))
  let count = parseInt(take(parts, cursor))
  doAssert count in 0..17
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
  doAssert checked(copyItemPayload(owner, payload)) == info.payloadBytes
  for i in info.payloadBytes..<payload.len: doAssert payload[i] == 0xA5 # No unused suffix writes.
  result = $uint32(info.service) & " " & hex(array[32, byte](info.codeHash)) & " " & $uint64(
      info.refineGas) & " " &
    $uint64(info.accumulateGas) & " " & $uint64(info.exports) & " " & hex(payload.toOpenArray(0,
        info.payloadBytes-1)) & " " & $info.imports
  let gas = info.refineGas
  info.refineGas = Gas(0)
  doAssert uint64(checked(workItemInfo(owner)).refineGas) == uint64(gas)
  doAssert importAt(owner, -1).error == PackageError.InvalidIndex
  doAssert importAt(owner, info.imports).error == PackageError.InvalidIndex
  # Imports retain sequence duplicates and both nominal identity alternatives.
  for i in 0..<info.imports:
    var reference = checked(importAt(owner, i))
    result.add(" " & fields(reference))
    let index = reference.index
    reference.index = ImportIndex(0)
    doAssert uint16(checked(importAt(owner, i)).index) == uint16(index)
  result.add(" " & $info.extrinsics)
  doAssert extrinsicAt(owner, -1).error == PackageError.InvalidIndex
  doAssert extrinsicAt(owner, info.extrinsics).error == PackageError.InvalidIndex
  # A locally mutated commitment must never alter immutable parent storage.
  for i in 0..<info.extrinsics:
    var commitment = checked(extrinsicAt(owner, i))
    result.add(" " & fields(commitment))
    let length = commitment.length
    commitment.length = ExtrinsicLength(0)
    doAssert uint32(checked(extrinsicAt(owner, i)).length) == uint32(length)

# Observe package blobs and child metadata through retained owners without exporting mutable snapshot storage.
proc fields(owner: OwnedWorkPackage): string =
  var info = checked(workPackageInfo(owner))
  result = $uint32(info.host) & " " & hex(array[32, byte](info.codeHash)) & " " & fields(info.context)
  # Selecting a named blob prevents detached offset extraction from the wrong parent buffer.
  for field in PackageBlob:
    let length = if field == PackageBlob.Authorization: info.authorizationBytes else: info.configurationBytes # The two metadata roles stay separate.
    var output = newSeq[byte](length+3)
    for i in 0..<output.len: output[i] = 0xA5 # Observe untouched suffix capacity for empty/nonempty blobs.
    doAssert checked(copyPackageBlob(owner, field, output)) == length
    for i in length..<output.len: doAssert output[i] == 0xA5 # Only selected owner-bound bytes were copied.
    result.add(" " & hex(output.toOpenArray(0, length-1)))
  result.add(" " & $info.items)
  doAssert workItemAt(owner, -1).error == PackageError.InvalidIndex
  doAssert workItemAt(owner, info.items).error == PackageError.InvalidIndex
  # Child handles retain the same immutable parent and expose no standalone spans.
  for i in 0..<info.items: result.add(" " & fields(checked(workItemAt(owner, i))))
  let slot = info.context.anchorSlot
  info.context.anchorSlot = AnchorSlot(0)
  doAssert uint32(checked(workPackageInfo(owner)).context.anchorSlot) == uint32(slot)

# Encode explicit fields and assert unchanged entire outputs on failure or untouched suffixes on success.
proc encodeRequest(parts: seq[string], config: PackageConfig) =
  let capacity = parseInt(parts[5])
  doAssert capacity in 0..33554432
  var output = newSeq[byte](capacity)
  # Every failure must leave the whole caller buffer unchanged, even for a late source error.
  for i in 0..<capacity: output[i] = 0xA5
  var cursor = 6
  var encoded: PackageResult[int]
  case parts[1]
  of "C": encoded = encodeRefinementContext(contextSource(parts, cursor),
      output) # Independently constructed context.
  of "R": encoded = encodeImportReference(importSource(parts, cursor),
      output) # Explicit packed-bit source alternative.
  of "X": encoded = encodeExtrinsicCommitment(commitmentSource(parts, cursor), output) # Full E4 length source.
  of "I": encoded = encodeWorkItem(itemSource(parts, cursor), config, output) # Complete nested item source.
  of "P": encoded = encodeWorkPackage(packageSource(parts, cursor), config,
      output) # Complete independent package source.
  else: doAssert false # The trusted protocol defines no other codec family.
  doAssert cursor == parts.len
  if encoded.error != PackageError.None:
    # Even complete earlier records may not write a prefix before a late source rejection.
    for octet in output: doAssert octet == 0xA5
    echo ($encoded.error).toLowerAscii()
  else:
    # Success writes exactly the selected wire prefix and leaves excess capacity untouched.
    for i in encoded.value..<output.len: doAssert output[i] == 0xA5
    echo hex(output.toOpenArray(0, encoded.value-1))

# Decode then independently observe fields; original input mutation must not affect owned success values.
proc decodeRequest(parts: seq[string], config: PackageConfig) =
  var input = unhex(parts[5])
  # Fixed components copy all their fields and return no borrowed coordinates.
  template fixedRequest(parser: untyped) =
    block:
      let parsed = parser(input)
      if parsed.error != PackageError.None:
        echo ($parsed.error).toLowerAscii() # No default record/progress is printed on rejection.
      else:
        for i in 0..<input.len: input[i] = 0 # Copied fixed fields survive source mutation.
        echo $parsed.value.consumed & " " & fields(parsed.value.value)
  case parts[1]
  of "C": fixedRequest(decodeRefinementContext) # Allocation-free fixed-context capture.
  of "R": fixedRequest(decodeImportReference) # Both selectors own complete identity/index values.
  of "X": fixedRequest(decodeExtrinsicCommitment) # Exact fixed advertised commitment.
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
      doAssert checked(encodeOwnedWorkItem(parsed.value.owner, output)) == consumed
      doAssert hex(output) == original
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
      doAssert checked(encodeOwnedWorkPackage(parsed.value.owner, output)) == consumed
      doAssert hex(output) == original
      echo $consumed & " " & observed
  else: doAssert false # Trusted fixtures never request an undefined family.

# Each request owns its temporary sources and no state survives to a subsequent operation.
for line in lines(paramStr(1)):
  if line.len > 0:
    # Blank lines contain no operation; all nonblank requests specify explicit chain/storage limits.
    let parts = line.splitWhitespace()
    doAssert parts.len >= 6
    let config = PackageConfig(refineGas: Gas(parseBiggestUInt(parts[2])), accumulateGas: Gas(
        parseBiggestUInt(parts[3])),
      maxBytes: ByteLimit(parseBiggestUInt(parts[4])))
    if parts[0] == "E": encodeRequest(parts, config) # Explicit source construction.
    else: decodeRequest(parts, config) # Byte-input parsing and independent field observation.
