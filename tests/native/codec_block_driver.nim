# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted full-parent adapter: independent typed child sources, ownership checks and exact
## prefix observation.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/parseutils
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/owned as codec_owned
import ../../src/codec/tickets as codec_tickets
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/guarantees as codec_guarantees
import ../../src/codec/disputes as codec_disputes
import ../../src/codec/header as codec_header

# Select expected parent success before reading complete values or consumed progress.
proc checked[T](parsed: FrameResult[T]): T =
  assert parsed.error == FrameError.None
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
proc unhex(text: string): seq[byte] {.raises.} =
  if text == "-": return @[] # Keep zero bytes as one trusted whitespace token.
  assert text.len mod 2 == 0 and text.len <= 4*1024*1024
  result = newSeq[byte](text.len div 2)
  # Every exact byte pair belongs to this independent request's input storage.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Check trusted fixture spelling before unsigned conversion.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

# Render exact child bytes for independent parent-boundary comparisons.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty field tokens when needed.
  result = ""
  # Every identity/proof byte contributes exactly two lowercase characters.
  for value in bytes: result.add(toHex(int(value), 2).toLowerAscii())

# Parse the full uint64 fixture domain without narrowing through signed host integers.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

# Parse eight explicit chain/resource fields without inferring parameters from serialized children.
proc config(parts: seq[string], cursor: var int): FrameConfig =
  # Each trusted numeric token has a separately named domain in the production configuration.
  template number(): uint64 =
    block:
      let value = unsigned(parts[cursor])
      inc cursor
      uint64(value)
  result = default(FrameConfig)
  result.cores = CoreCount(number())
  result.validators = ValidatorCount(number())
  result.epochSlots = EpochSlots(number())
  result.ticketLimit = TicketLimit(number())
  result.preimages.items = ElementLimit(number())
  result.preimages.perBlob = ByteLimit(number())
  result.preimages.totalBlobBytes = ByteLimit(number())
  result.maxBytes = ByteLimit(number())

# Re-emission observes the exact component prefix and verifies untouched extra destination capacity.
proc wire[kind: static[ComponentKind]](owner: Component[kind]): string =
  let info = checked(componentInfo(owner))
  var output = newSeq[byte](info.consumed+3)
  for i in 0..<output.len: output[i] = 0xA5 # All unused suffix bytes must survive component extraction.
  assert checked(encodeComponent(owner, output)) == info.consumed
  for i in info.consumed..<output.len: assert output[i] == 0xA5 # Exact private prefix only.
  result = hex(output.toOpenArray(0, info.consumed-1))

# Check interoperability with existing child APIs and verify returned records are independent mutable copies.
proc leaves(owner: OwnedExtrinsic) =
  let ticketPart = checked(extrinsicTickets(owner))
  var records = checked(readTickets(ticketPart))
  assert records.len == checked(componentInfo(ticketPart)).records
  # Exercise copy independence only when a complete first ticket exists.
  if records.len > 0:
    let attempt = records[0].attempt
    records[0].attempt = TicketAttempt(uint8(attempt) xor 255) # Mutating a returned copy cannot touch the retained component.
    assert checked(readTickets(ticketPart))[0].attempt == attempt
  let assurancePart = checked(extrinsicAssurances(owner))
  var recordsA = checked(readAssurances(assurancePart))
  assert recordsA.len == checked(componentInfo(assurancePart)).records
  # A nonempty assurance sequence permits a mutation without fabricating a record.
  if recordsA.len > 0:
    let validator = recordsA[0].validator
    recordsA[0].validator = ValidatorIndex(65535) # Copied typed records are not mutable snapshot storage.
    assert uint16(checked(readAssurances(assurancePart))[0].validator) == uint16(validator)
  let preimagePart = checked(extrinsicPreimages(owner))
  let preimages = readPreimages(preimagePart)
  assert preimages.error == OwnershipError.None
  let preimageInfo = ownedInfo(preimages.value)
  assert preimageInfo.error == OwnershipError.None
  assert preimageInfo.value.blobCount == checked(componentInfo(preimagePart)).records
  var bytesP = newSeq[byte](preimageInfo.value.consumed)
  assert encodeOwned(preimages.value, bytesP).error == OwnershipError.None
  assert hex(bytesP) == wire(preimagePart)
  let guaranteePart = checked(extrinsicGuarantees(owner))
  let guarantees = readGuarantees(guaranteePart)
  assert guarantees.error == GuaranteeError.None
  var bytesG = newSeq[byte](guarantees.value.consumed)
  assert encodeOwnedGuarantees(guarantees.value.owner, bytesG).error == GuaranteeError.None
  assert hex(bytesG) == wire(guaranteePart)
  let disputePart = checked(extrinsicDisputes(owner))
  let disputes = readDisputes(disputePart)
  assert disputes.error == DisputeError.None
  var bytesD = newSeq[byte](disputes.value.info.consumed)
  assert encodeOwnedDisputes(disputes.value.owner, bytesD).error == DisputeError.None
  assert hex(bytesD) == wire(disputePart)

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

# Decode untrusted input, destroy its original contents, then observe independently expected immutable children.
proc decodeRequest(parts: seq[string]) {.raises.} =
  var cursor = 2
  let limits = config(parts, cursor)
  assert parts.len == cursor+1
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
      var output = newSeq[byte](count+3)
      for i in 0..<output.len: output[i] = 0xA5 # Extra destination capacity is outside this frame.
      assert checked(encodeOwnedExtrinsic(parsed.value.owner, output)) == count
      assert hex(output.toOpenArray(0, count-1)) == original
      for i in count..<output.len: assert output[i] == 0xA5 # Preserve the unused suffix.
      echo $count & " " & observed
  else:
    # Block decoding verifies the sealed header and all five children as one operation.
    assert parts[1] == "B"
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
      let fullRead = readHeader(headerPart)
      assert fullRead.error == HeaderError.None
      var headerBytes = newSeq[byte](fullRead.value.consumed)
      assert encodeOwnedHeader(fullRead.value.owner, headerBytes).error == HeaderError.None
      assert hex(headerBytes) == wire(headerPart)
      let child = checked(blockExtrinsic(parsed.value.owner))
      let logical = fields(child)
      let split = logical.splitWhitespace()
      # Print all six independent counts before all six exact child encodings.
      let counts = "1 " & split.toOpenArray(0, 4).join(" ")
      let bytes = wire(headerPart) & " " & split.toOpenArray(5, 9).join(" ")
      var output = newSeq[byte](count+3)
      for i in 0..<output.len: output[i] = 0xA5 # Extra destination capacity is outside this frame.
      assert checked(encodeOwnedBlock(parsed.value.owner, output)) == count
      assert hex(output.toOpenArray(0, count-1)) == original
      for i in count..<output.len: assert output[i] == 0xA5 # Preserve the unused suffix.
      echo $count & " " & counts & " " & bytes

# Encode from independently supplied typed children; the parent decoder never constructs the encoding source.
proc encodeRequest(parts: seq[string]) {.raises.} =
  var cursor = 2
  let captureLimits = config(parts, cursor)
  let targetLimits = config(parts, cursor)
  let capacity = parseInt(parts[cursor]); inc cursor
  assert capacity in 0..2097152
  var output = newSeq[byte](capacity)
  for i in 0..<output.len: output[i] = 0xA5 # Failed component capture and parent preflight both preserve the entire destination.
  var source = default(Extrinsic)
  var headerPart = default(HeaderComponent)
  # Capture the complete header source independently of the parent decoder.
  if parts[1] == "B":
    var bytes = unhex(parts[cursor]); inc cursor
    let parsed = decodeComponent[ComponentKind.Header](bytes, captureLimits)
    # A failed child capture must leave the entire destination unchanged.
    if parsed.error != FrameError.None:
      for octet in output: assert octet == 0xA5 # Parent encoding has not begun.
      echo reason(parsed)
      return
    assert parsed.value.consumed == bytes.len
    headerPart = parsed.value.owner
    for i in 0..<bytes.len: bytes[i] = 0 # Retained snapshots own their bytes.
  # Capture the complete tickets source independently of the parent decoder.
  block:
    var bytes = unhex(parts[cursor]); inc cursor
    let parsed = decodeComponent[ComponentKind.Tickets](bytes, captureLimits)
    # A failed child capture must leave the entire destination unchanged.
    if parsed.error != FrameError.None:
      for octet in output: assert octet == 0xA5 # Parent encoding has not begun.
      echo reason(parsed)
      return
    assert parsed.value.consumed == bytes.len
    source.tickets = parsed.value.owner
    for i in 0..<bytes.len: bytes[i] = 0 # Retained snapshots own their bytes.
  # Capture the complete preimages source independently of the parent decoder.
  block:
    var bytes = unhex(parts[cursor]); inc cursor
    let parsed = decodeComponent[ComponentKind.Preimages](bytes, captureLimits)
    # A failed child capture must leave the entire destination unchanged.
    if parsed.error != FrameError.None:
      for octet in output: assert octet == 0xA5 # Parent encoding has not begun.
      echo reason(parsed)
      return
    assert parsed.value.consumed == bytes.len
    source.preimages = parsed.value.owner
    for i in 0..<bytes.len: bytes[i] = 0 # Retained snapshots own their bytes.
  # Capture the complete guarantees source independently of the parent decoder.
  block:
    var bytes = unhex(parts[cursor]); inc cursor
    let parsed = decodeComponent[ComponentKind.Guarantees](bytes, captureLimits)
    # A failed child capture must leave the entire destination unchanged.
    if parsed.error != FrameError.None:
      for octet in output: assert octet == 0xA5 # Parent encoding has not begun.
      echo reason(parsed)
      return
    assert parsed.value.consumed == bytes.len
    source.guarantees = parsed.value.owner
    for i in 0..<bytes.len: bytes[i] = 0 # Retained snapshots own their bytes.
  # Capture the complete assurances source independently of the parent decoder.
  block:
    var bytes = unhex(parts[cursor]); inc cursor
    let parsed = decodeComponent[ComponentKind.Assurances](bytes, captureLimits)
    # A failed child capture must leave the entire destination unchanged.
    if parsed.error != FrameError.None:
      for octet in output: assert octet == 0xA5 # Parent encoding has not begun.
      echo reason(parsed)
      return
    assert parsed.value.consumed == bytes.len
    source.assurances = parsed.value.owner
    for i in 0..<bytes.len: bytes[i] = 0 # Retained snapshots own their bytes.
  # Capture the complete disputes source independently of the parent decoder.
  block:
    var bytes = unhex(parts[cursor]); inc cursor
    let parsed = decodeComponent[ComponentKind.Disputes](bytes, captureLimits)
    # A failed child capture must leave the entire destination unchanged.
    if parsed.error != FrameError.None:
      for octet in output: assert octet == 0xA5 # Parent encoding has not begun.
      echo reason(parsed)
      return
    assert parsed.value.consumed == bytes.len
    source.disputes = parsed.value.owner
    for i in 0..<bytes.len: bytes[i] = 0 # Retained snapshots own their bytes.
  assert cursor == parts.len
  var encoded: FrameResult[int] = default(FrameResult[int])
  # Extrinsics have five components; block requests below additionally require a sealed header.
  if parts[1] == "E":
    encoded = encodeExtrinsic(source, targetLimits,
        output) # Direct typed source encoding, with no parent decode round trip.
  else:
    # Blocks retain a separately validated extrinsic source alongside their header.
    let captured = ownExtrinsic(source, captureLimits)
    assert captured.error == FrameError.None
    let blockSource = Block(header: headerPart, extrinsic: captured.value)
    encoded = encodeBlock(blockSource, targetLimits,
        output) # Both children remain subject to the new shared block policy.
  # A final source, policy or output failure must preserve every destination byte.
  if encoded.error != FrameError.None:
    for octet in output: assert octet == 0xA5 # A late nested failure leaves even the header destination untouched.
    echo reason(encoded)
  else:
    # Successful output must end exactly at the independently observed parent boundary.
    for i in encoded.value..<output.len: assert output[i] ==
        0xA5 # Success emits only the complete parent prefix.
    echo hex(output.toOpenArray(0, encoded.value-1))

# Each request owns its temporary state and never borrows bytes retained by a previous operation.
try:
  for line in lines(paramStr(1)):
    # Ignore blank trusted batch lines without issuing an accidental codec operation.
    if line.len > 0:
      let parts = line.splitWhitespace() # Blank fixture lines contain no trusted operation.
      if parts[0] == "D": decodeRequest(parts) # Untrusted byte framing and immutable child observation.
      else: encodeRequest(parts) # Independent typed source construction and atomic writes.
except:
  # Trusted fixture transport failures must fail distinctly from typed codec rejection.
  quit(2)
