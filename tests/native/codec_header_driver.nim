# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted independent typed-source and field-observation adapter for header/marker codecs.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/parseutils
import ../../src/codec/header as codec_header
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/tickets as codec_tickets

# Every expected-success getter selects the result branch before reading any value or progress.
proc checked[T](parsed: HeaderResult[T]): T =
  assert parsed.error == HeaderError.None
  parsed.value

# Decode bounded public fixture text into adapter-owned mutable octets.
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

# Observe complete public fields without relying on a header encode/decode round trip.
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

# Construct nominal fixed source fields directly, independently of production decoding.
proc fixed[N: static[int]](text: string): array[N, byte] {.raises.} =
  result = default(array[N, byte])
  let bytes = unhex(text)
  assert bytes.len == N
  # Exact byte copies preserve source roles without parsing any production wire structure.
  for i in 0..<N: result[i] = bytes[i]

# Consume one trusted source token without imposing a wire representation on its future value.
proc take(parts: seq[string], cursor: var int): string =
  result = parts[cursor]
  inc cursor

# Build fixed ticket sources with the full representable E1 attempt domain.
proc ticketSource(parts: seq[string], cursor: var int): WinningTicket {.raises.} =
  result = default(WinningTicket)
  result.id = WinningTicketId(fixed[32](take(parts, cursor)))
  let attempt = parseInt(take(parts, cursor))
  assert attempt in 0..255
  result.attempt = TicketAttempt(attempt)

# Build complete optional epoch sources, including invalid counts for atomic rejection tests.
proc epochSource(parts: seq[string], cursor: var int): EpochMarker {.raises.} =
  let present = parseInt(take(parts, cursor))
  assert present in 0..1
  if present == 0:
    return absentEpoch() # Absence has no default validator/entropy source fields.
  let entropy = EpochEntropy(fixed[32](take(parts, cursor)))
  let ticketsEntropy = TicketsEntropy(fixed[32](take(parts, cursor)))
  let count = parseInt(take(parts, cursor))
  assert count in 0..1024
  result = presentEpoch(entropy, ticketsEntropy, newSeq[EpochValidator](count))
  # Every pair is explicitly constructed in supplied validator-index order.
  for i in 0..<count:
    editEpochValidators(result)[i].bandersnatch = HeaderBsKey(fixed[32](take(parts, cursor)))
    editEpochValidators(result)[i].ed25519 = HeaderEdKey(fixed[32](take(parts, cursor)))

# Trusted source fields carry a count although the actual winner wire deliberately does not.
proc winnersSource(parts: seq[string], cursor: var int): WinnersMarker {.raises.} =
  let present = parseInt(take(parts, cursor))
  assert present in 0..1
  if present == 0:
    return absentWinners() # No ticket source exists in the absent alternative.
  let count = parseInt(take(parts, cursor))
  assert count in 0..600
  result = presentWinners(newSeq[WinningTicket](count))
  # Explicit ticket records preserve duplicates and arbitrary supplied slot order.
  for i in 0..<count: editWinnerTickets(result)[i] = ticketSource(parts, cursor)

# Construct all unsigned fields by name, without the production header/marker decoder creating any source.
proc unsignedSource(parts: seq[string], cursor: var int): UnsignedHeader {.raises.} =
  result = default(UnsignedHeader)
  result.parent = HeaderParent(fixed[32](take(parts, cursor)))
  result.priorState = PriorStateRoot(fixed[32](take(parts, cursor)))
  result.extrinsics = ExtrinsicRoot(fixed[32](take(parts, cursor)))
  result.slot = HeaderSlot(unsigned(take(parts, cursor)))
  result.epoch = epochSource(parts, cursor)
  result.winners = winnersSource(parts, cursor)
  result.author = AuthorIndex(parseInt(take(parts, cursor)))
  result.entropyProof = HeaderEntropyProof(fixed[96](take(parts, cursor)))
  let count = parseInt(take(parts, cursor))
  assert count in 0..33
  result.offenders = newSeq[HeaderEdKey](count)
  # Offender sequences preserve order and cross-section duplicates rather than becoming sorted sets.
  for i in 0..<count: result.offenders[i] = HeaderEdKey(fixed[32](take(parts, cursor)))

# Observe each complete fixed ticket field without using the fixed record encoder.
proc fields(value: WinningTicket): string =
  hex(array[32, byte](value.id)) & " " & $uint8(value.attempt)

# Observe copied epoch metadata and every indexed key pair through its original retained marker.
proc fields(owner: OwnedEpochMarker): string =
  let info = checked(epochMarkerInfo(owner))
  assert epochValidatorAt(owner, -1).error == HeaderError.InvalidIndex
  if not info.present:
    assert epochValidatorAt(owner, 0).error == HeaderError.InvalidIndex # Absent markers cannot publish validator slots.
    return "0"
  result = "1 " & hex(array[32, byte](info.entropy)) & " " & hex(array[32, byte](
      info.ticketsEntropy)) & " " & $info.validators
  assert epochValidatorAt(owner, info.validators).error == HeaderError.InvalidIndex
  # Key getter copies cannot mutate the immutable snapshot's indexed validator identity.
  for i in 0..<info.validators:
    var pair = checked(epochValidatorAt(owner, i))
    result.add(" " & hex(array[32, byte](pair.bandersnatch)) & " " & hex(array[32, byte](pair.ed25519)))
    let key = pair.ed25519
    pair.ed25519 = HeaderEdKey(default(array[32, byte]))
    assert array[32, byte](checked(epochValidatorAt(owner, i)).ed25519) == array[32, byte](key)

# Observe every slot-ordered winner without exposing a mutable ticket sequence or detached offsets.
proc fields(owner: OwnedWinnersMarker): string =
  let info = checked(winnersMarkerInfo(owner))
  assert winningTicketAt(owner, -1).error == HeaderError.InvalidIndex
  if not info.present:
    assert winningTicketAt(owner, 0).error == HeaderError.InvalidIndex # Absence is not a present empty winner list.
    return "0"
  result = "1 " & $info.tickets
  assert winningTicketAt(owner, info.tickets).error == HeaderError.InvalidIndex
  # Mutating each fixed ticket copy must leave its retained identifier and attempt intact.
  for i in 0..<info.tickets:
    var ticket = checked(winningTicketAt(owner, i))
    result.add(" " & fields(ticket))
    let id = ticket.id
    ticket.id = WinningTicketId(default(array[32, byte]))
    assert array[32, byte](checked(winningTicketAt(owner, i)).id) == array[32, byte](id)

# Observe exact unsigned logical fields through copied metadata and retained child marker handles.
proc fields(owner: OwnedUnsignedHeader): string =
  var info = checked(unsignedHeaderInfo(owner))
  result = hex(array[32, byte](info.parent)) & " " & hex(array[32, byte](info.priorState)) & " " &
    hex(array[32, byte](info.extrinsics)) & " " & $uint32(info.slot) & " " & fields(checked(
        headerEpoch(owner))) &
    " " & fields(checked(headerWinners(owner))) & " " & $uint16(info.author) & " " &
    hex(array[96, byte](info.entropyProof)) & " " & $info.offenders
  assert headerOffenderAt(owner, -1).error == HeaderError.InvalidIndex
  assert headerOffenderAt(owner, info.offenders).error == HeaderError.InvalidIndex
  # Offender observation preserves the exact supplied concatenation, including repeated/descending keys.
  for i in 0..<info.offenders: result.add(" " & hex(array[32, byte](checked(headerOffenderAt(owner, i)))))
  let slot = info.slot
  info.slot = HeaderSlot(0)
  assert uint32(checked(unsignedHeaderInfo(owner)).slot) == uint32(slot)

# Run one explicit encode request and check every failure for whole-output atomicity.
proc encodeRequest(parts: seq[string], config: HeaderConfig) {.raises.} =
  let capacity = parseInt(parts[6])
  assert capacity in 0..2097152
  var output = newSeq[byte](capacity)
  for i in 0..<capacity: output[i] = 0xA5 # Sentinels catch writes before late marker/author failures.
  var cursor = 7
  var encoded: HeaderResult[int] = default(HeaderResult[int])
  case parts[1]
  of "T": encoded = encodeWinningTicket(ticketSource(parts, cursor),
      output) # Independently constructed fixed record.
  of "E": encoded = encodeEpochMarker(epochSource(parts, cursor), config,
      output) # Explicit optional source tuple.
  of "W": encoded = encodeWinnersMarker(winnersSource(parts, cursor), config,
      output) # Explicit fixed-length ticket source.
  of "U": encoded = encodeUnsignedHeader(unsignedSource(parts, cursor), config,
      output) # Complete signing fields without seal.
  of "H":
    var value = Header(unsigned: unsignedSource(parts, cursor))
    value.seal = HeaderSeal(fixed[96](take(parts, cursor)))
    encoded = encodeHeader(value, config, output) # Seal has its own exact nominal source field.
  else: assert false # The trusted protocol defines no other family.
  assert cursor == parts.len
  if encoded.error != HeaderError.None:
    for value in output: assert value == 0xA5 # Failure cannot emit any earlier source prefix.
    echo ($encoded.error).toLowerAscii()
  else:
    for i in encoded.value..<output.len: assert output[i] == 0xA5 # Success preserves extra caller capacity.
    echo hex(output.toOpenArray(0, encoded.value-1))

# Decode byte input, destroy caller source contents, then independently observe every retained logical field.
proc decodeRequest(parts: seq[string], config: HeaderConfig) {.raises.} =
  var input = unhex(parts[6])
  # Each decoder uses its concrete result and owner type, preserving exact signing and marker intervals.
  case parts[1]
  of "T":
    # Independently observe this exact wire family after validating its complete selected prefix.
    let parsed = decodeWinningTicket(input)
    if parsed.error != HeaderError.None:
      echo ($parsed.error).toLowerAscii() # Failed scans contain no default values, owners or progress.
    else:
      let completed = parsed.value
      let consumed = completed.consumed
      # Fixed ticket fields own their bytes independently of the erased original input.
      for octet in input.mitems: octet = 0
      echo $consumed & " " & fields(completed.value)
  of "E":
    # Independently observe this exact wire family after validating its complete selected prefix.
    let parsed = decodeEpochMarker(input, config)
    if parsed.error != HeaderError.None:
      echo ($parsed.error).toLowerAscii() # Failed scans contain no default values, owners or progress.
    else:
      let completed = parsed.value
      let consumed = completed.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      # Caller mutation covers unrelated trailing bytes as well as the complete captured prefix.
      for octet in input.mitems: octet = 0
      let observed = fields(completed.owner)
      var output = newSeq[byte](consumed+3)
      # Owner re-emission must leave every destination byte outside its exact interval untouched.
      for octet in output.mitems: octet = 0xA5
      assert checked(encodeOwnedEpochMarker(completed.owner, output)) == consumed
      assert hex(output.toOpenArray(0, consumed-1)) == original
      for i in consumed..<output.len: assert output[i] == 0xA5
      echo $consumed & " " & observed
  of "W":
    # Independently observe this exact wire family after validating its complete selected prefix.
    let parsed = decodeWinnersMarker(input, config)
    if parsed.error != HeaderError.None:
      echo ($parsed.error).toLowerAscii() # Failed scans contain no default values, owners or progress.
    else:
      let completed = parsed.value
      let consumed = completed.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      # Caller mutation covers unrelated trailing bytes as well as the complete captured prefix.
      for octet in input.mitems: octet = 0
      let observed = fields(completed.owner)
      var output = newSeq[byte](consumed+3)
      # Owner re-emission must leave every destination byte outside its exact interval untouched.
      for octet in output.mitems: octet = 0xA5
      assert checked(encodeOwnedWinnersMarker(completed.owner, output)) == consumed
      assert hex(output.toOpenArray(0, consumed-1)) == original
      for i in consumed..<output.len: assert output[i] == 0xA5
      echo $consumed & " " & observed
  of "U":
    # Independently observe this exact wire family after validating its complete selected prefix.
    let parsed = decodeUnsignedHeader(input, config)
    if parsed.error != HeaderError.None:
      echo ($parsed.error).toLowerAscii() # Failed scans contain no default values, owners or progress.
    else:
      let completed = parsed.value
      let consumed = completed.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      # Caller mutation covers unrelated trailing bytes as well as the complete captured prefix.
      for octet in input.mitems: octet = 0
      let observed = fields(completed.owner)
      var output = newSeq[byte](consumed+3)
      # Owner re-emission must leave every destination byte outside its exact interval untouched.
      for octet in output.mitems: octet = 0xA5
      assert checked(encodeOwnedUnsignedHeader(completed.owner, output)) == consumed
      assert hex(output.toOpenArray(0, consumed-1)) == original
      for i in consumed..<output.len: assert output[i] == 0xA5
      echo $consumed & " " & observed
  of "H":
    # Independently observe this exact wire family after validating its complete selected prefix.
    let parsed = decodeHeader(input, config)
    if parsed.error != HeaderError.None:
      echo ($parsed.error).toLowerAscii() # Failed scans contain no default values, owners or progress.
    else:
      let completed = parsed.value
      let consumed = completed.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      # Caller mutation covers unrelated trailing bytes as well as the complete captured prefix.
      for octet in input.mitems: octet = 0
      let info = checked(headerInfo(completed.owner))
      let unsigned = checked(unsignedPart(completed.owner))
      let observed = fields(unsigned) & " " & hex(array[96, byte](info.seal))
      var output = newSeq[byte](consumed+3)
      # Owner re-emission must leave every destination byte outside its exact interval untouched.
      for octet in output.mitems: octet = 0xA5
      assert checked(encodeOwnedHeader(completed.owner, output)) == consumed
      assert hex(output.toOpenArray(0, consumed-1)) == original
      for i in consumed..<output.len: assert output[i] == 0xA5
      let unsignedBytes = info.unsigned.consumed
      var signing = newSeq[byte](unsignedBytes+3)
      # The signing prefix includes all unsigned fields and omits only the final seal.
      for octet in signing.mitems: octet = 0xA5
      assert checked(encodeOwnedUnsignedHeader(unsigned, signing)) == unsignedBytes
      assert hex(signing.toOpenArray(0, unsignedBytes-1)) == original[0..<2*unsignedBytes]
      for i in unsignedBytes..<signing.len: assert signing[i] == 0xA5
      echo $consumed & " " & observed
  else: assert false # Undefined family names are trusted harness failures.

# Direct sealed-header inspection returns copied metadata without allocating retained owners.
proc inspectRequest(parts: seq[string], config: HeaderConfig) {.raises.} =
  assert parts[1] == "H"
  let parsed = inspectHeader(unhex(parts[6]), config)
  if parsed.error != HeaderError.None:
    echo ($parsed.error).toLowerAscii() # No prefix or fixed metadata from a failed full scan.
  else:
    # Observe all copied fixed fields and both full/signing extents independently of capture/re-emission.
    let info = parsed.value
    let value = info.unsigned
    echo $info.consumed & " " & $value.consumed & " " & hex(array[32, byte](value.parent)) & " " &
      hex(array[32, byte](value.priorState)) & " " & hex(array[32, byte](value.extrinsics)) & " " &
      $uint32(value.slot) & " " & $uint16(value.author) & " " & hex(array[96, byte](
          value.entropyProof)) & " " &
      $value.offenders & " " & hex(array[96, byte](info.seal))

# Requests share no mutable state; file/parse errors must fail rather than skip coverage.
try:
  # Whole-file allocation belongs only to the trusted fixture adapter.
  for line in readFile(paramStr(1)).splitLines():
    if line.len > 0:
      # Each nonblank operation supplies explicit chain/profile/resource domains.
      let parts = line.splitWhitespace()
      assert parts.len >= 7
      let config = HeaderConfig(cores: CoreCount(unsigned(parts[2])),
        authorValidators: ValidatorCount(unsigned(parts[3])), epochSlots: EpochSlots(unsigned(parts[
            4])),
        maxBytes: ByteLimit(unsigned(parts[5])))
      if parts[0] == "E": encodeRequest(parts, config) # Independent source construction.
      elif parts[0] == "Q": inspectRequest(parts, config) # Allocation-free sealed-header metadata.
      else: decodeRequest(parts, config) # Exact wire parsing and independent field observation.
except:
  # Malformed trusted text and missing files are failures, never alternate protocol interpretations.
  quit 2
