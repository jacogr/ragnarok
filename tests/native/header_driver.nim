## Trusted independent typed-source and field-observation adapter for header/marker codecs.
import std/[os, strutils]
import ../../src/codec/[header, bounded, assurances, tickets]

# Every expected-success getter selects the result branch before reading any value or progress.
proc checked[T](parsed: HeaderResult[T]): T =
  doAssert parsed.error == HeaderError.None
  parsed.value

# Decode bounded public fixture text into adapter-owned mutable octets.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Keep zero bytes as one trusted whitespace token.
  doAssert text.len mod 2 == 0 and text.len <= 4*1024*1024
  result = newSeq[byte](text.len div 2)
  # Every exact byte pair belongs to this independent request's input storage.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Observe complete public fields without relying on a header encode/decode round trip.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty field tokens when needed.
  # Every identity/proof byte contributes exactly two lowercase characters.
  for value in bytes: result.add(toHex(value, 2).toLowerAscii())

# Construct nominal fixed source fields directly, independently of production decoding.
proc fixed[N: static int](text: string): array[N, byte] =
  let bytes = unhex(text)
  doAssert bytes.len == N
  # Exact byte copies preserve source roles without parsing any production wire structure.
  for i in 0..<N: result[i] = bytes[i]

# Consume one trusted source token without imposing a wire representation on its future value.
proc take(parts: seq[string], cursor: var int): string =
  result = parts[cursor]
  inc cursor

# Build fixed ticket sources with the full representable E1 attempt domain.
proc ticketSource(parts: seq[string], cursor: var int): WinningTicket =
  result.id = WinningTicketId(fixed[32](take(parts, cursor)))
  let attempt = parseInt(take(parts, cursor))
  doAssert attempt in 0..255
  result.attempt = TicketAttempt(attempt)

# Build complete optional epoch sources, including invalid counts for atomic rejection tests.
proc epochSource(parts: seq[string], cursor: var int): EpochMarker =
  let present = parseInt(take(parts, cursor))
  doAssert present in 0..1
  if present == 0:
    return EpochMarker(present: false) # Absence has no default validator/entropy source fields.
  let entropy = EpochEntropy(fixed[32](take(parts, cursor)))
  let ticketsEntropy = TicketsEntropy(fixed[32](take(parts, cursor)))
  let count = parseInt(take(parts, cursor))
  doAssert count in 0..1024
  result = EpochMarker(present: true, entropy: entropy, ticketsEntropy: ticketsEntropy,
    validators: newSeq[EpochValidator](count))
  # Every pair is explicitly constructed in supplied validator-index order.
  for i in 0..<count:
    result.validators[i].bandersnatch = HeaderBsKey(fixed[32](take(parts, cursor)))
    result.validators[i].ed25519 = HeaderEdKey(fixed[32](take(parts, cursor)))

# Trusted source fields carry a count although the actual winner wire deliberately does not.
proc winnersSource(parts: seq[string], cursor: var int): WinnersMarker =
  let present = parseInt(take(parts, cursor))
  doAssert present in 0..1
  if present == 0:
    return WinnersMarker(present: false) # No ticket source exists in the absent alternative.
  let count = parseInt(take(parts, cursor))
  doAssert count in 0..600
  result = WinnersMarker(present: true, tickets: newSeq[WinningTicket](count))
  # Explicit ticket records preserve duplicates and arbitrary supplied slot order.
  for i in 0..<count: result.tickets[i] = ticketSource(parts, cursor)

# Construct all unsigned fields by name, without the production header/marker decoder creating any source.
proc unsignedSource(parts: seq[string], cursor: var int): UnsignedHeader =
  result.parent = HeaderParent(fixed[32](take(parts, cursor)))
  result.priorState = PriorStateRoot(fixed[32](take(parts, cursor)))
  result.extrinsics = ExtrinsicRoot(fixed[32](take(parts, cursor)))
  result.slot = HeaderSlot(parseBiggestUInt(take(parts, cursor)))
  result.epoch = epochSource(parts, cursor)
  result.winners = winnersSource(parts, cursor)
  result.author = AuthorIndex(parseInt(take(parts, cursor)))
  result.entropyProof = HeaderEntropyProof(fixed[96](take(parts, cursor)))
  let count = parseInt(take(parts, cursor))
  doAssert count in 0..33
  result.offenders = newSeq[HeaderEdKey](count)
  # Offender sequences preserve order and cross-section duplicates rather than becoming sorted sets.
  for i in 0..<count: result.offenders[i] = HeaderEdKey(fixed[32](take(parts, cursor)))

# Observe each complete fixed ticket field without using the fixed record encoder.
proc fields(value: WinningTicket): string =
  hex(array[32, byte](value.id)) & " " & $uint8(value.attempt)

# Observe copied epoch metadata and every indexed key pair through its original retained marker.
proc fields(owner: OwnedEpochMarker): string =
  let info = checked(epochMarkerInfo(owner))
  doAssert epochValidatorAt(owner, -1).error == HeaderError.InvalidIndex
  if not info.present:
    doAssert epochValidatorAt(owner, 0).error == HeaderError.InvalidIndex # Absent markers cannot publish validator slots.
    return "0"
  result = "1 " & hex(array[32, byte](info.entropy)) & " " & hex(array[32, byte](
      info.ticketsEntropy)) & " " & $info.validators
  doAssert epochValidatorAt(owner, info.validators).error == HeaderError.InvalidIndex
  # Key getter copies cannot mutate the immutable snapshot's indexed validator identity.
  for i in 0..<info.validators:
    var pair = checked(epochValidatorAt(owner, i))
    result.add(" " & hex(array[32, byte](pair.bandersnatch)) & " " & hex(array[32, byte](pair.ed25519)))
    let key = pair.ed25519
    pair.ed25519 = HeaderEdKey(default(array[32, byte]))
    doAssert array[32, byte](checked(epochValidatorAt(owner, i)).ed25519) == array[32, byte](key)

# Observe every slot-ordered winner without exposing a mutable ticket sequence or detached offsets.
proc fields(owner: OwnedWinnersMarker): string =
  let info = checked(winnersMarkerInfo(owner))
  doAssert winningTicketAt(owner, -1).error == HeaderError.InvalidIndex
  if not info.present:
    doAssert winningTicketAt(owner, 0).error == HeaderError.InvalidIndex # Absence is not a present empty winner list.
    return "0"
  result = "1 " & $info.tickets
  doAssert winningTicketAt(owner, info.tickets).error == HeaderError.InvalidIndex
  # Mutating each fixed ticket copy must leave its retained identifier and attempt intact.
  for i in 0..<info.tickets:
    var ticket = checked(winningTicketAt(owner, i))
    result.add(" " & fields(ticket))
    let id = ticket.id
    ticket.id = WinningTicketId(default(array[32, byte]))
    doAssert array[32, byte](checked(winningTicketAt(owner, i)).id) == array[32, byte](id)

# Observe exact unsigned logical fields through copied metadata and retained child marker handles.
proc fields(owner: OwnedUnsignedHeader): string =
  var info = checked(unsignedHeaderInfo(owner))
  result = hex(array[32, byte](info.parent)) & " " & hex(array[32, byte](info.priorState)) & " " &
    hex(array[32, byte](info.extrinsics)) & " " & $uint32(info.slot) & " " & fields(checked(
        headerEpoch(owner))) &
    " " & fields(checked(headerWinners(owner))) & " " & $uint16(info.author) & " " &
    hex(array[96, byte](info.entropyProof)) & " " & $info.offenders
  doAssert headerOffenderAt(owner, -1).error == HeaderError.InvalidIndex
  doAssert headerOffenderAt(owner, info.offenders).error == HeaderError.InvalidIndex
  # Offender observation preserves the exact supplied concatenation, including repeated/descending keys.
  for i in 0..<info.offenders: result.add(" " & hex(array[32, byte](checked(headerOffenderAt(owner, i)))))
  let slot = info.slot
  info.slot = HeaderSlot(0)
  doAssert uint32(checked(unsignedHeaderInfo(owner)).slot) == uint32(slot)

# Verify immutable re-emission against the original prefix and untouched destination suffix sentinels.
template reemit(owner, encoder, consumed, original: untyped) =
  block:
    var output = newSeq[byte](consumed+3)
    for i in 0..<output.len: output[i] = 0xA5 # Every unselected destination byte must survive unchanged.
    doAssert checked(encoder(owner, output)) == consumed
    doAssert hex(output.toOpenArray(0, consumed-1)) == original
    for i in consumed..<output.len: doAssert output[i] == 0xA5 # Owner copies emit only their validated prefix.

# Run one explicit encode request and check every failure for whole-output atomicity.
proc encodeRequest(parts: seq[string], config: HeaderConfig) =
  let capacity = parseInt(parts[6])
  doAssert capacity in 0..2097152
  var output = newSeq[byte](capacity)
  for i in 0..<capacity: output[i] = 0xA5 # Sentinels catch writes before late marker/author failures.
  var cursor = 7
  var encoded: HeaderResult[int]
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
  else: doAssert false # The trusted protocol defines no other family.
  doAssert cursor == parts.len
  if encoded.error != HeaderError.None:
    for value in output: doAssert value == 0xA5 # Failure cannot emit any earlier source prefix.
    echo ($encoded.error).toLowerAscii()
  else:
    for i in encoded.value..<output.len: doAssert output[i] == 0xA5 # Success preserves extra caller capacity.
    echo hex(output.toOpenArray(0, encoded.value-1))

# Decode byte input, destroy caller source contents, then independently observe every retained logical field.
proc decodeRequest(parts: seq[string], config: HeaderConfig) =
  var input = unhex(parts[6])
  # Marker/unsigned owners all expose the same exact-prefix capture and re-emission contract.
  template ownedRequest(parser, encoder: untyped) =
    block:
      let parsed = parser(input, config)
      if parsed.error != HeaderError.None:
        echo ($parsed.error).toLowerAscii() # Failed scans carry no owner or progress.
      else:
        let consumed = parsed.value.consumed
        let original = hex(input.toOpenArray(0, consumed-1))
        for i in 0..<input.len: input[i] = 0 # Mutate every borrowed source byte, including trailing data.
        let observed = fields(parsed.value.owner)
        reemit(parsed.value.owner, encoder, consumed, original)
        echo $consumed & " " & observed
  case parts[1]
  of "T":
    let parsed = decodeWinningTicket(input)
    if parsed.error != HeaderError.None:
      echo ($parsed.error).toLowerAscii() # Fixed-ticket failures contain no default identifier/attempt.
    else:
      for i in 0..<input.len: input[i] = 0 # Complete fixed records also outlive their source contents.
      echo $parsed.value.consumed & " " & fields(parsed.value.value)
  of "E": ownedRequest(decodeEpochMarker, encodeOwnedEpochMarker) # Standalone epoch owner.
  of "W": ownedRequest(decodeWinnersMarker, encodeOwnedWinnersMarker) # Standalone winner owner.
  of "U": ownedRequest(decodeUnsignedHeader, encodeOwnedUnsignedHeader) # Standalone unsigned owner.
  of "H":
    let parsed = decodeHeader(input, config)
    if parsed.error != HeaderError.None:
      echo ($parsed.error).toLowerAscii() # A truncated seal cannot publish a full-header owner.
    else:
      let consumed = parsed.value.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      for i in 0..<input.len: input[i] = 0 # Retained markers/proofs must be independent of all source bytes.
      let info = checked(headerInfo(parsed.value.owner))
      let unsigned = checked(unsignedPart(parsed.value.owner))
      let observed = fields(unsigned) & " " & hex(array[96, byte](info.seal))
      reemit(parsed.value.owner, encodeOwnedHeader, consumed, original)
      let unsignedBytes = info.unsigned.consumed
      reemit(unsigned, encodeOwnedUnsignedHeader, unsignedBytes, original[0..<2*unsignedBytes])
      echo $consumed & " " & observed
  else: doAssert false # No undefined parser family is reachable from trusted requests.

# Requests share a process but never retain mutable source state across operations.
for line in lines(paramStr(1)):
  if line.len > 0:
    let parts = line.splitWhitespace() # Blank lines contain no trusted operation.
    doAssert parts.len >= 7
    let config = HeaderConfig(cores: CoreCount(parseBiggestUInt(parts[2])),
      authorValidators: ValidatorCount(parseBiggestUInt(parts[3])), epochSlots: EpochSlots(
          parseBiggestUInt(parts[4])),
      maxBytes: ByteLimit(parseBiggestUInt(parts[5])))
    if parts[0] == "E": encodeRequest(parts, config) # Independent typed source construction.
    else: decodeRequest(parts, config) # Byte parsing and explicit field observation.
