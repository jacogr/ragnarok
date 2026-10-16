## Trusted full-parent adapter: independent typed child sources, ownership checks and exact prefix observation.
import std/[os, strutils]
import ../../src/[block_codec, bounded, composite, owned, tickets, assurances, guarantees, disputes, header]

# Select expected parent success before reading complete values or consumed progress.
proc checked[T](parsed: FrameResult[T]): T =
  doAssert parsed.error == FrameError.None
  parsed.value

# Render parent/typed-child failures without parsing diagnostics or publishing default records.
proc reason[T](parsed: FrameResult[T]): string =
  if parsed.error != FrameError.InvalidComponent:
    return ($parsed.error).toLowerAscii() # Parent failures contain no selected component cause.
  let cause = parsed.cause
  case cause.kind
  of ComponentKind.Header: result = "header:" & ($cause.headerError).toLowerAscii() # Preserve exact nested header failure.
  of ComponentKind.Tickets: result = "tickets:" & ($cause.ticketError).toLowerAscii() # Preserve exact nested tickets failure.
  of ComponentKind.Preimages: result = "preimages:" & ($cause.preimageError).toLowerAscii() # Preserve exact nested preimages failure.
  of ComponentKind.Guarantees: result = "guarantees:" & ($cause.guaranteeError).toLowerAscii() # Preserve exact nested guarantees failure.
  of ComponentKind.Assurances: result = "assurances:" & ($cause.assuranceError).toLowerAscii() # Preserve exact nested assurances failure.
  of ComponentKind.Disputes: result = "disputes:" & ($cause.disputeError).toLowerAscii() # Preserve exact nested disputes failure.

# Decode bounded public fixture text into independent mutable request-owned bytes.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # One token preserves empty untrusted input.
  doAssert text.len mod 2 == 0 and text.len <= 4*1024*1024
  result = newSeq[byte](text.len div 2)
  # Every octet belongs to the adapter and may be overwritten after successful capture.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Exact public fixture bytes are observed independently of whole-parent encode/decode round trips.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty fields in trusted whitespace transport.
  for value in bytes: result.add(toHex(value, 2).toLowerAscii()) # Exact octet order remains visible.

# Parse eight explicit chain/resource fields without inferring parameters from serialized children.
proc config(parts: seq[string], cursor: var int): FrameConfig =
  # Each trusted numeric token has a separately named domain in the production configuration.
  template number(): uint64 =
    block:
      let value = parseBiggestUInt(parts[cursor])
      inc cursor
      uint64(value)
  result.cores = CoreCount(number())
  result.validators = ValidatorCount(number())
  result.epochSlots = EpochSlots(number())
  result.ticketLimit = TicketLimit(number())
  result.preimages.items = ElementLimit(number())
  result.preimages.perBlob = ByteLimit(number())
  result.preimages.totalBlobBytes = ByteLimit(number())
  result.maxBytes = ByteLimit(number())

# Re-emission observes the exact component prefix and verifies untouched extra destination capacity.
proc wire[kind: static ComponentKind](owner: Component[kind]): string =
  let info = checked(componentInfo(owner))
  var output = newSeq[byte](info.consumed+3)
  for i in 0..<output.len: output[i] = 0xA5 # All unused suffix bytes must survive component extraction.
  doAssert checked(encodeComponent(owner, output)) == info.consumed
  for i in info.consumed..<output.len: doAssert output[i] == 0xA5 # Exact private prefix only.
  result = hex(output.toOpenArray(0, info.consumed-1))

# Check interoperability with existing child APIs and verify returned records are independent mutable copies.
proc leaves(owner: OwnedExtrinsic) =
  let ticketPart = checked(extrinsicTickets(owner))
  var records = checked(readTickets(ticketPart))
  doAssert records.len == checked(componentInfo(ticketPart)).records
  # Exercise copy independence only when a complete first ticket exists.
  if records.len > 0:
    let attempt = records[0].attempt
    records[0].attempt = TicketAttempt(uint8(attempt) xor 255) # Mutating a returned copy cannot touch the retained component.
    doAssert checked(readTickets(ticketPart))[0].attempt == attempt
  let assurancePart = checked(extrinsicAssurances(owner))
  var recordsA = checked(readAssurances(assurancePart))
  doAssert recordsA.len == checked(componentInfo(assurancePart)).records
  # A nonempty assurance sequence permits a mutation without fabricating a record.
  if recordsA.len > 0:
    let validator = recordsA[0].validator
    recordsA[0].validator = ValidatorIndex(65535) # Copied typed records are not mutable snapshot storage.
    doAssert uint16(checked(readAssurances(assurancePart))[0].validator) == uint16(validator)
  let preimagePart = checked(extrinsicPreimages(owner))
  let preimages = readPreimages(preimagePart)
  doAssert preimages.error == OwnershipError.None
  let preimageInfo = ownedInfo(preimages.value)
  doAssert preimageInfo.error == OwnershipError.None
  doAssert preimageInfo.value.blobCount == checked(componentInfo(preimagePart)).records
  var bytesP = newSeq[byte](preimageInfo.value.consumed)
  doAssert encodeOwned(preimages.value, bytesP).error == OwnershipError.None
  doAssert hex(bytesP) == wire(preimagePart)
  let guaranteePart = checked(extrinsicGuarantees(owner))
  let guarantees = readGuarantees(guaranteePart)
  doAssert guarantees.error == GuaranteeError.None
  var bytesG = newSeq[byte](guarantees.value.consumed)
  doAssert encodeOwnedGuarantees(guarantees.value.owner, bytesG).error == GuaranteeError.None
  doAssert hex(bytesG) == wire(guaranteePart)
  let disputePart = checked(extrinsicDisputes(owner))
  let disputes = readDisputes(disputePart)
  doAssert disputes.error == DisputeError.None
  var bytesD = newSeq[byte](disputes.value.info.consumed)
  doAssert encodeOwnedDisputes(disputes.value.owner, bytesD).error == DisputeError.None
  doAssert hex(bytesD) == wire(disputePart)

# Observe every child boundary/count independently, using matching opaque getter handles rather than detached spans.
proc fields(owner: OwnedExtrinsic): string =
  let info = checked(extrinsicInfo(owner))
  result = $info.tickets & " " & $info.preimages & " " & $info.guarantees & " " & $info.assurances &
      " " & $info.disputes
  result.add(" " & wire(checked(extrinsicTickets(owner))))
  result.add(" " & wire(checked(extrinsicPreimages(owner))))
  result.add(" " & wire(checked(extrinsicGuarantees(owner))))
  result.add(" " & wire(checked(extrinsicAssurances(owner))))
  result.add(" " & wire(checked(extrinsicDisputes(owner))))
  leaves(owner)

# Assert exact whole-owner re-emission and preserved suffix, alongside independent boundary observation.
template reemit(owner, encoder, consumed, original: untyped) =
  block:
    var output = newSeq[byte](consumed+3)
    for i in 0..<output.len: output[i] = 0xA5 # Extra destination bytes remain outside the selected parent prefix.
    doAssert checked(encoder(owner, output)) == consumed
    doAssert hex(output.toOpenArray(0, consumed-1)) == original
    for i in consumed..<output.len: doAssert output[i] == 0xA5 # Parent copies cannot write unrelated capacity.

# Decode untrusted input, destroy its original contents, then observe independently expected immutable children.
proc decodeRequest(parts: seq[string]) =
  var cursor = 2
  let limits = config(parts, cursor)
  doAssert parts.len == cursor+1
  var input = unhex(parts[cursor])
  # Extrinsics have five components; block requests below additionally require a sealed header.
  if parts[1] == "E":
    let parsed = decodeExtrinsic(input, limits)
    # Failed whole-frame decoding may print only its selected failure reason.
    if parsed.error != FrameError.None:
      echo reason(parsed) # A late failed component publishes neither earlier children nor a parent cursor.
    else:
      # Only a complete capture authorizes immutable child observation and re-emission.
      let count = parsed.value.consumed
      let original = hex(input.toOpenArray(0, count-1))
      for i in 0..<input.len: input[i] = 0 # Retained child coordinates are unrelated to caller storage after capture.
      let observed = fields(parsed.value.owner)
      reemit(parsed.value.owner, encodeOwnedExtrinsic, count, original)
      echo $count & " " & observed
  else:
    # Block decoding verifies the sealed header and all five children as one operation.
    doAssert parts[1] == "B"
    let parsed = decodeBlock(input, limits)
    # Failed whole-frame decoding may print only its selected failure reason.
    if parsed.error != FrameError.None:
      echo reason(parsed) # No retained header escapes when the final disputes component fails.
    else:
      # Only a complete capture authorizes immutable child observation and re-emission.
      let count = parsed.value.consumed
      let original = hex(input.toOpenArray(0, count-1))
      for i in 0..<input.len: input[i] = 0 # Include unrelated trailing bytes in source mutation.
      let headerPart = checked(blockHeader(parsed.value.owner))
      let header = readHeader(headerPart)
      doAssert header.error == HeaderError.None
      var headerBytes = newSeq[byte](header.value.consumed)
      doAssert encodeOwnedHeader(header.value.owner, headerBytes).error == HeaderError.None
      doAssert hex(headerBytes) == wire(headerPart)
      let child = checked(blockExtrinsic(parsed.value.owner))
      let logical = fields(child)
      let split = logical.splitWhitespace()
      # Print all six independent counts before all six exact child encodings.
      let counts = "1 " & split[0..4].join(" ")
      let bytes = wire(headerPart) & " " & split[5..9].join(" ")
      reemit(parsed.value.owner, encodeOwnedBlock, count, original)
      echo $count & " " & counts & " " & bytes

# Encode from independently supplied typed children; the parent decoder never constructs the encoding source.
proc encodeRequest(parts: seq[string]) =
  var cursor = 2
  let captureLimits = config(parts, cursor)
  let targetLimits = config(parts, cursor)
  let capacity = parseInt(parts[cursor]); inc cursor
  doAssert capacity in 0..2097152
  var output = newSeq[byte](capacity)
  for i in 0..<output.len: output[i] = 0xA5 # Failed component capture and parent preflight both preserve the entire destination.
  # A fixture token denotes one exact independent child value, rather than a decoded parent slice.
  template load(target: untyped, kind: static ComponentKind) =
    block:
      var bytes = unhex(parts[cursor]); inc cursor
      let parsed = decodeComponent[kind](bytes, captureLimits)
      # Failed independent source capture leaves no child for parent encoding.
      if parsed.error != FrameError.None:
        for octet in output: doAssert octet == 0xA5 # No parent encoder is invoked without complete typed source children.
        echo reason(parsed)
        return
      doAssert parsed.value.consumed == bytes.len
      target = parsed.value.owner
      for i in 0..<bytes.len: bytes[i] = 0 # Source owner must remain independent of construction input.
  var source: Extrinsic
  var headerPart: HeaderComponent
  if parts[1] == "B": load(headerPart, ComponentKind.Header) # Blocks need a complete sealed header component.
  load(source.tickets, ComponentKind.Tickets)
  load(source.preimages, ComponentKind.Preimages)
  load(source.guarantees, ComponentKind.Guarantees)
  load(source.assurances, ComponentKind.Assurances)
  load(source.disputes, ComponentKind.Disputes)
  doAssert cursor == parts.len
  var encoded: FrameResult[int]
  # Extrinsics have five components; block requests below additionally require a sealed header.
  if parts[1] == "E":
    encoded = encodeExtrinsic(source, targetLimits,
        output) # Direct typed source encoding, with no parent decode round trip.
  else:
    # Blocks retain a separately validated extrinsic source alongside their header.
    let captured = ownExtrinsic(source, captureLimits)
    doAssert captured.error == FrameError.None
    let blockSource = Block(header: headerPart, extrinsic: captured.value)
    encoded = encodeBlock(blockSource, targetLimits,
        output) # Both children remain subject to the new shared block policy.
  # A final source, policy or output failure must preserve every destination byte.
  if encoded.error != FrameError.None:
    for octet in output: doAssert octet == 0xA5 # A late nested failure leaves even the header destination untouched.
    echo reason(encoded)
  else:
    # Successful output must end exactly at the independently observed parent boundary.
    for i in encoded.value..<output.len: doAssert output[i] ==
        0xA5 # Success emits only the complete parent prefix.
    echo hex(output.toOpenArray(0, encoded.value-1))

# Each request owns its temporary state and never borrows bytes retained by a previous operation.
for line in lines(paramStr(1)):
  # Ignore blank trusted batch lines without issuing an accidental codec operation.
  if line.len > 0:
    let parts = line.splitWhitespace() # Blank fixture lines contain no trusted operation.
    if parts[0] == "D": decodeRequest(parts) # Untrusted byte framing and immutable child observation.
    else: encodeRequest(parts) # Independent typed source construction and atomic writes.
