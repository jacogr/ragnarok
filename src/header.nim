## GP 0.8.0 C.2 header/marker codecs; signatures and state-dependent marker eligibility remain external.
import ./[natural, bounded, assurances, tickets]

type
  # Parent block identity is distinct from the header's two other commitments.
  HeaderParent* = distinct array[32, byte]
  # This root commits to the prior state rather than a work-report anchor state.
  PriorStateRoot* = distinct array[32, byte]
  # Header extrinsic commitment is separate from a work-item's individual input-data hash.
  ExtrinsicRoot* = distinct array[32, byte]
  # Header timeslots use E4 and cannot be silently substituted for lookup/report slots.
  HeaderSlot* = distinct uint32
  # Author indices use E2 into the posterior active validator population supplied by context.
  AuthorIndex* = distinct uint16
  # Epoch randomness accumulator encoding is distinct from the ticket-contest randomness.
  EpochEntropy* = distinct array[32, byte]
  # Ticket-contest entropy retains its separate nominal role in an epoch marker.
  TicketsEntropy* = distinct array[32, byte]
  # Encoded Bandersnatch validator key; structural decoding does not validate its curve point.
  HeaderBsKey* = distinct array[32, byte]
  # Encoded Ed25519 key used in epoch pairs and newly offending validator markers.
  HeaderEdKey* = distinct array[32, byte]
  # A ticket identifier is an opaque hash, not a RingVRF proof or arbitrary root.
  WinningTicketId* = distinct array[32, byte]
  # Full opaque 96-byte entropy-yielding VRF encoding; no verification claim is made here.
  HeaderEntropyProof* = distinct array[96, byte]
  # Full opaque 96-byte block seal is nominally distinct from the entropy proof.
  HeaderSeal* = distinct array[96, byte]
  # Epoch length is an explicit chain parameter; winner sequences have no count on the wire.
  EpochSlots* = distinct uint64
  # One indexed validator pair owns its complete key encodings and preserves validator order.
  EpochValidator* = object
    bandersnatch*: HeaderBsKey
    ed25519*: HeaderEdKey
  # Public byref source records keep caller-storage identity stable for preflight alias checks.
  # Winning tickets are fixed owned hash/E1 records; TicketAttempt reuses the existing entry-index domain.
  WinningTicket* {.byref.} = object
    id*: WinningTicketId
    attempt*: TicketAttempt
  # Encoder source is absent or contains exactly the two entropies and stable borrowed validator sequence.
  EpochMarker* {.byref.} = object
    case present*: bool
    of true:
      entropy*: EpochEntropy # Present markers alone contain epoch randomness.
      ticketsEntropy*: TicketsEntropy
      validators*: seq[EpochValidator]
    of false:
      discard                # Absent markers contain no default key sequence or entropy value.
                # Winner sources are absent or borrow exactly the configured epoch's sequence of complete tickets.
  WinnersMarker* {.byref.} = object
    case present*: bool
    of true:
      tickets*: seq[WinningTicket] # Present markers contain no separate encoded count.
    of false:
      discard                      # Absence occupies only its canonical zero discriminator.
                # Stable borrowed header encoding sources; fixed fields own bytes and all sequences remain stable during calls.
  UnsignedHeader* {.byref.} = object
    parent*: HeaderParent
    priorState*: PriorStateRoot
    extrinsics*: ExtrinsicRoot
    slot*: HeaderSlot
    epoch*: EpochMarker
    winners*: WinnersMarker
    author*: AuthorIndex
    entropyProof*: HeaderEntropyProof
    offenders*: seq[HeaderEdKey]
  # A complete header appends the seal to the entire unsigned serialization, including offender keys.
  Header* {.byref.} = object
    unsigned*: UnsignedHeader
    seal*: HeaderSeal
  # Core ceiling bounds pending epoch key counts independently of the author's posterior-set ceiling.
  HeaderConfig* = object
    cores*: CoreCount
    authorValidators*: ValidatorCount
    epochSlots*: EpochSlots
    maxBytes*: ByteLimit
  # Failures/default results never carry a record, owner, length or partial parser cursor.
  HeaderError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, Truncated, NonCanonical, LimitExceeded,
    InvalidTag, InvalidAuthor, OutputTooSmall, AliasedBuffers, LengthOverflow, InvalidOwner, InvalidIndex
  # Success must be selected explicitly before reading the complete application value.
  HeaderResult*[T] = object
    case error*: HeaderError
    of HeaderError.None:
      value*: T # Only successful operations publish values or progress.
    else:
      discard   # Rejections carry just their typed reason.
                # Fixed winning-ticket decoding is allocation-free and reports one exact prefix.
  WinningTicketRead* = object
    value*: WinningTicket
    consumed*: int
  # Copied marker metadata cannot expose or rebind its retained validator storage.
  EpochMarkerInfo* = object
    case present*: bool
    of true:
      entropy*: EpochEntropy # Entropies and count exist only for the present alternative.
      ticketsEntropy*: TicketsEntropy
      validators*: int
    of false:
      discard                # An absent marker has no validator count to mistake for a present empty population.
                # Copied winner metadata contains only the present sequence length, never a detached byte span.
  WinnersMarkerInfo* = object
    case present*: bool
    of true:
      tickets*: int # This equals the configured epoch length for every retained success.
    of false:
      discard       # No default ticket sequence is published by absence.
                    # Header metadata copies complete fixed fields and scalar marker/sequence information.
  UnsignedHeaderInfo* = object
    parent*: HeaderParent
    priorState*: PriorStateRoot
    extrinsics*: ExtrinsicRoot
    slot*: HeaderSlot
    author*: AuthorIndex
    entropyProof*: HeaderEntropyProof
    offenders*, consumed*: int
  # Full metadata contains the exact unsigned prefix and final copied seal in distinct nominal roles.
  HeaderInfo* = object
    unsigned*: UnsignedHeaderInfo
    seal*: HeaderSeal
    consumed*: int
  # All coordinates remain private and are captured alongside the matching immutable wire bytes.
  Layout = object
    unsigned: UnsignedHeaderInfo
    epoch: EpochMarkerInfo
    winners: WinnersMarkerInfo
    epochStart, epochLength, validatorStart: int
    winnersStart, winnersLength, ticketStart, offenderStart, consumed: int
  # Acyclic ARC snapshot is immutable after its completely validated prefix has been captured.
  HeaderData = ref object
    wire: seq[byte]
    layout: Layout
  # Full header handles retain private bytes and cannot be constructed from an unsigned-only snapshot.
  OwnedHeader* = object
    data: HeaderData
  # Unsigned handles retain the whole parent snapshot when selected from a sealed header.
  OwnedUnsignedHeader* = object
    data: HeaderData
  # Epoch handles retain their original header/standalone marker without exposing coordinates.
  OwnedEpochMarker* = object
    data: HeaderData
  # Winner handles retain their original header/standalone marker without exporting mutable tickets.
  OwnedWinnersMarker* = object
    data: HeaderData
  # Successful full decoding binds exact consumed progress to its owner.
  HeaderRead* = object
    owner*: OwnedHeader
    consumed*: int
  # Successful unsigned decoding has its own handle type, distinct from a sealed header.
  UnsignedHeaderRead* = object
    owner*: OwnedUnsignedHeader
    consumed*: int
  # Standalone epoch decoding returns an owner even for a validated absent marker.
  EpochMarkerRead* = object
    owner*: OwnedEpochMarker
    consumed*: int
  # Standalone winner decoding returns an owner even for a validated absent marker.
  WinnersMarkerRead* = object
    owner*: OwnedWinnersMarker
    consumed*: int

# Full-profile convenience leaves the serialized byte budget an explicit caller resource decision.
proc fullHeaderConfig*(maxBytes: ByteLimit): HeaderConfig {.raises: [].} =
  HeaderConfig(cores: CoreCount(341), authorValidators: ValidatorCount(1023),
    epochSlots: EpochSlots(600), maxBytes: maxBytes)

# Validate GP validator domains and a positive epoch length before any untrusted byte or source access.
proc validConfig(config: HeaderConfig): bool {.raises: [].} =
  assurances.validConfig(AssuranceConfig(cores: config.cores,
      validators: config.authorValidators)) and
    uint64(config.epochSlots) > 0

# Copy an exact owned identity/proof after its enclosing input extent has been checked.
proc fixed[N: static int](input: openArray[byte], start: int): array[N, byte] {.raises: [].} =
  # No caller pointer escapes these exact value copies.
  for i in 0..<N: result[i] = input[start+i]

# Decode only previously proved E2/E4 fields in little-endian order.
proc scalar(input: openArray[byte], start, width: int): uint32 {.raises: [].} =
  # Shifts stay within the maximum four-octet scalar used by this codec.
  for i in 0..<width: result = result or (uint32(input[start+i]) shl (8*i))

# Prove an unsigned count's complete input extent before narrowing, multiplying or reading its bytes.
proc extent(input: openArray[byte], cursor: int, count: uint64, stride: int,
    config: HeaderConfig): HeaderError {.raises: [].} =
  # Division handles even a maximal configured epoch without overflowing count times stride.
  if count > uint64((input.len-cursor) div stride):
    return HeaderError.Truncated
  # Presence proves the product/endpoint fit host int; retained prefix budget is independent.
  if uint64(cursor+int(count)*stride) > uint64(config.maxBytes):
    return HeaderError.LimitExceeded
  HeaderError.None

# Read a canonical bounded natural; partial cursor updates remain private on failure.
proc number(input: openArray[byte], cursor: var int, ceiling: uint64,
    config: HeaderConfig): HeaderResult[int] {.raises: [].} =
  let parsed = natural.decode(input.toOpenArray(cursor, input.high))
  # Preserve truncated versus overlong framing before interpreting a count.
  if not parsed.ok:
    return HeaderResult[int](error: if parsed.error == natural.truncated: HeaderError.Truncated
      else: HeaderError.NonCanonical) # An overlong discriminator cannot select another valid wire representation.
  cursor += int(parsed.consumed)
  # Every caller's count ceiling is at most 1023, so checking it also proves host narrowing.
  if uint64(cursor) > uint64(config.maxBytes) or uint64(parsed.value) > ceiling:
    return HeaderResult[int](error: HeaderError.LimitExceeded)
  HeaderResult[int](error: HeaderError.None, value: int(uint64(parsed.value)))

# Read a canonical optional marker discriminator without allocating or accepting other octet tags.
proc tag(input: openArray[byte], cursor: var int, config: HeaderConfig): HeaderResult[
    bool] {.raises: [].} =
  let checked = extent(input, cursor, 1, 1, config)
  # Input/budget checks precede the first discriminator byte access.
  if checked != HeaderError.None:
    return HeaderResult[bool](error: checked)
  let value = input[cursor]
  # Only canonical absent/present alternatives exist.
  if value > 1:
    return HeaderResult[bool](error: HeaderError.InvalidTag)
  inc cursor
  HeaderResult[bool](error: HeaderError.None, value: value == 1)

# Scan a complete epoch marker into bounded metadata; key order/encodings remain opaque at this layer.
proc scanEpoch(input: openArray[byte], cursor: var int, config: HeaderConfig,
    layout: var Layout): HeaderError {.raises: [].} =
  layout.epochStart = cursor
  let present = tag(input, cursor, config)
  # A missing/invalid marker never publishes default entropy or validator metadata.
  if present.error != HeaderError.None:
    return present.error
  layout.epoch = EpochMarkerInfo(present: present.value)
  # Present epoch markers have two entropies and a variable GP valcount sequence.
  if present.value:
    let checked = extent(input, cursor, 1, 64, config)
    # Both complete entropy identities are required before copying either.
    if checked != HeaderError.None:
      return checked
    let entropy = EpochEntropy(fixed[32](input, cursor))
    let ticketsEntropy = TicketsEntropy(fixed[32](input, cursor+32))
    cursor += 64
    let count = number(input, cursor, 3*uint64(config.cores), config)
    # A canonical bounded count precedes key access or iteration.
    if count.error != HeaderError.None:
      return count.error
    # GP valcount is multiples of three from six through three times cores.
    if count.value < 6 or count.value mod 3 != 0:
      return HeaderError.LimitExceeded
    let keys = extent(input, cursor, uint64(count.value), 64, config)
    # One complete Bandersnatch/Ed25519 pair per indexed validator.
    if keys != HeaderError.None:
      return keys
    layout.validatorStart = cursor
    layout.epoch = EpochMarkerInfo(present: true, entropy: entropy,
      ticketsEntropy: ticketsEntropy, validators: count.value)
    cursor += count.value*64
  layout.epochLength = cursor-layout.epochStart
  HeaderError.None

# Scan a complete winner marker; a present sequence has exactly configured epoch length and no count.
proc scanWinners(input: openArray[byte], cursor: var int, config: HeaderConfig,
    layout: var Layout): HeaderError {.raises: [].} =
  layout.winnersStart = cursor
  let present = tag(input, cursor, config)
  # Invalid optional framing cannot authorize any ticket metadata.
  if present.error != HeaderError.None:
    return present.error
  layout.winners = WinnersMarkerInfo(present: present.value)
  # Every fixed 33-byte ticket must be available before converting the configured count to host int.
  if present.value:
    let checked = extent(input, cursor, uint64(config.epochSlots), 33, config)
    # Huge positive configurations fail without arithmetic overflow or allocation.
    if checked != HeaderError.None:
      return checked
    layout.ticketStart = cursor
    layout.winners = WinnersMarkerInfo(present: true, tickets: int(uint64(config.epochSlots)))
    cursor += layout.winners.tickets*33
  layout.winnersLength = cursor-layout.winnersStart
  HeaderError.None

# Scan one unsigned/full header without input-derived allocation or mutable caller writes.
proc scanHeader(input: openArray[byte], config: HeaderConfig, sealed: bool): HeaderResult[
    Layout] {.raises: [].} =
  # Configuration determines structural author/epoch domains and cannot be inferred from input.
  if not validConfig(config):
    return HeaderResult[Layout](error: HeaderError.InvalidConfig)
  var layout: Layout
  var cursor = 0
  let prefix = extent(input, cursor, 1, 100, config)
  # Three hashes and fixed E4 slot form the complete prefix.
  if prefix != HeaderError.None:
    return HeaderResult[Layout](error: prefix)
  layout.unsigned.parent = HeaderParent(fixed[32](input, 0))
  layout.unsigned.priorState = PriorStateRoot(fixed[32](input, 32))
  layout.unsigned.extrinsics = ExtrinsicRoot(fixed[32](input, 64))
  layout.unsigned.slot = HeaderSlot(scalar(input, 96, 4))
  cursor = 100
  let epoch = scanEpoch(input, cursor, config, layout)
  # Epoch failure discards the complete header scan.
  if epoch != HeaderError.None:
    return HeaderResult[Layout](error: epoch)
  let winners = scanWinners(input, cursor, config, layout)
  # No guessed count or marker length is used.
  if winners != HeaderError.None:
    return HeaderResult[Layout](error: winners)
  let credentials = extent(input, cursor, 1, 98, config)
  # Complete E2 author and entropy proof are required.
  if credentials != HeaderError.None:
    return HeaderResult[Layout](error: credentials)
  let author = scalar(input, cursor, 2)
  # E2 representability alone is not author-domain membership.
  if uint64(author) >= uint64(config.authorValidators):
    return HeaderResult[Layout](error: HeaderError.InvalidAuthor)
  layout.unsigned.author = AuthorIndex(author)
  layout.unsigned.entropyProof = HeaderEntropyProof(fixed[96](input, cursor+2))
  cursor += 98
  let count = number(input, cursor, 32, config)
  # At most sixteen culprit plus sixteen fault keys are possible.
  if count.error != HeaderError.None:
    return HeaderResult[Layout](error: count.error)
  let offenders = extent(input, cursor, uint64(count.value), 32, config)
  # Offender order and cross-section duplicates are preserved exactly.
  if offenders != HeaderError.None:
    return HeaderResult[Layout](error: offenders)
  layout.offenderStart = cursor
  layout.unsigned.offenders = count.value
  cursor += count.value*32
  layout.unsigned.consumed = cursor
  # A full header appends the complete opaque seal after all unsigned fields, including offenders.
  if sealed:
    let seal = extent(input, cursor, 1, 96, config)
    # A truncated final seal cannot expose an unsigned success as a full header.
    if seal != HeaderError.None:
      return HeaderResult[Layout](error: seal)
    cursor += 96
  layout.consumed = cursor
  HeaderResult[Layout](error: HeaderError.None, value: layout)

# Capture only a completely scanned prefix in private immutable acyclic ARC storage.
proc capture(input: openArray[byte], layout: Layout): HeaderData {.raises: [].} =
  result = HeaderData(layout: layout, wire: newSeq[byte](layout.consumed))
  # Exclude unrelated trailing bytes from the snapshot and its resource accounting.
  for i in 0..<result.wire.len: result.wire[i] = input[i]

# Decode a full header only after all framing, counts, author policy and final seal bytes validate.
proc decodeHeader*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    HeaderRead] {.raises: [].} =
  let scanned = scanHeader(input, config, true)
  # No attacker-derived allocation occurs for failed/default results.
  if scanned.error != HeaderError.None:
    return HeaderResult[HeaderRead](error: scanned.error)
  HeaderResult[HeaderRead](error: HeaderError.None, value: HeaderRead(
    owner: OwnedHeader(data: capture(input, scanned.value)), consumed: scanned.value.consumed))

# Decode an unsigned header as its own prefix/owner type; no seal is required or guessed.
proc decodeUnsignedHeader*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    UnsignedHeaderRead] {.raises: [].} =
  let scanned = scanHeader(input, config, false)
  # Every failed scan discards its private marker coordinates and progress.
  if scanned.error != HeaderError.None:
    return HeaderResult[UnsignedHeaderRead](error: scanned.error)
  HeaderResult[UnsignedHeaderRead](error: HeaderError.None, value: UnsignedHeaderRead(
    owner: OwnedUnsignedHeader(data: capture(input, scanned.value)),
        consumed: scanned.value.consumed))

# Decode a standalone epoch marker, preserving initialized absence separately from a default owner.
proc decodeEpochMarker*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    EpochMarkerRead] {.raises: [].} =
  # Reject invalid chain domains before input access.
  if not validConfig(config):
    return HeaderResult[EpochMarkerRead](error: HeaderError.InvalidConfig)
  var layout: Layout
  var cursor = 0
  let error = scanEpoch(input, cursor, config, layout)
  # No partial entropy/key owner is published.
  if error != HeaderError.None:
    return HeaderResult[EpochMarkerRead](error: error)
  layout.consumed = cursor
  HeaderResult[EpochMarkerRead](error: HeaderError.None, value: EpochMarkerRead(
    owner: OwnedEpochMarker(data: capture(input, layout)), consumed: cursor))

# Decode standalone winners using the caller's epoch length rather than a nonexistent sequence count.
proc decodeWinnersMarker*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    WinnersMarkerRead] {.raises: [].} =
  # Require explicit valid chain configuration first.
  if not validConfig(config):
    return HeaderResult[WinnersMarkerRead](error: HeaderError.InvalidConfig)
  var layout: Layout
  var cursor = 0
  let error = scanWinners(input, cursor, config, layout)
  # Fixed ticket extents must all validate before capture.
  if error != HeaderError.None:
    return HeaderResult[WinnersMarkerRead](error: error)
  layout.consumed = cursor
  HeaderResult[WinnersMarkerRead](error: HeaderError.None, value: WinnersMarkerRead(
    owner: OwnedWinnersMarker(data: capture(input, layout)), consumed: cursor))

# Fixed winner-ticket decoding owns every identifier/attempt byte and needs no chain configuration.
proc decodeWinningTicket*(input: openArray[byte]): HeaderResult[WinningTicketRead] {.raises: [].} =
  # Identifier and E1 attempt must both exist.
  if input.len < 33:
    return HeaderResult[WinningTicketRead](error: HeaderError.Truncated)
  HeaderResult[WinningTicketRead](error: HeaderError.None, value: WinningTicketRead(consumed: 33,
    value: WinningTicket(id: WinningTicketId(fixed[32](input, 0)), attempt: TicketAttempt(input[32]))))

# Grow a measured prefix only after proving its host extent, including multiplication, cannot overflow.
proc grow(size: var int, count, stride: int): HeaderError {.raises: [].} =
  # Counts cannot wrap an encoder capacity/alias calculation.
  if count > (high(int)-size) div stride:
    return HeaderError.LengthOverflow
  size += count*stride
  HeaderError.None

# Measure/validate epoch sources without allocating, sorting or verifying opaque keys.
proc epochSize(value: EpochMarker, config: HeaderConfig): HeaderResult[int] {.raises: [].} =
  var size = 1
  # Absence carries no validator sequence or entropy fields to inspect.
  if value.present:
    let count = value.validators.len
    # Pending population follows valcount, independently of author population.
    if count < 6 or uint64(count) > 3*uint64(config.cores) or count mod 3 != 0:
      return HeaderResult[int](error: HeaderError.LimitExceeded)
    size += 64+int(natural.encode(JamNatural(count)).len)+64*count
  HeaderResult[int](error: HeaderError.None, value: size)

# Measure winners with exact caller epoch cardinality and safe host arithmetic.
proc winnersSize(value: WinnersMarker, config: HeaderConfig): HeaderResult[int] {.raises: [].} =
  var size = 1
  # Present winners are fixed-length tuples, never a variable-count sequence.
  if value.present:
    # An encoder must not silently add/drop epoch tickets.
    if uint64(value.tickets.len) != uint64(config.epochSlots):
      return HeaderResult[int](error: HeaderError.LimitExceeded)
    let error = grow(size, value.tickets.len, 33)
    # Host extent must be representable before capacity checks.
    if error != HeaderError.None:
      return HeaderResult[int](error: error)
  HeaderResult[int](error: HeaderError.None, value: size)

# Measure every unsigned source field before byte policy, capacity or output writes.
proc unsignedSize(value: UnsignedHeader, config: HeaderConfig): HeaderResult[int] {.raises: [].} =
  let epoch = epochSize(value.epoch, config)
  # Invalid late nested sources cannot emit a header prefix.
  if epoch.error != HeaderError.None:
    return epoch
  let winners = winnersSize(value.winners, config)
  # Exact configured ticket count is checked before author/output policy.
  if winners.error != HeaderError.None:
    return winners
  # Do not narrow an out-of-domain author.
  if uint64(value.author) >= uint64(config.authorValidators):
    return HeaderResult[int](error: HeaderError.InvalidAuthor)
  # Judgments derive at most 16+16 new offender entries.
  if value.offenders.len > 32:
    return HeaderResult[int](error: HeaderError.LimitExceeded)
  var size = 198+epoch.value
  let winnerGrowth = grow(size, winners.value, 1)
  # A complete winner tuple can be large under custom epoch parameters.
  if winnerGrowth != HeaderError.None:
    return HeaderResult[int](error: winnerGrowth)
  let suffix = int(natural.encode(JamNatural(value.offenders.len)).len)+32*value.offenders.len
  let suffixGrowth = grow(size, suffix, 1)
  # Complete offender count/keys must fit after winners.
  if suffixGrowth != HeaderError.None:
    return HeaderResult[int](error: suffixGrowth)
  HeaderResult[int](error: HeaderError.None, value: size)

# Compare addresses by distance so even near-address-limit buffers need no overflowing endpoint sum.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool {.raises: [].} =
  # Empty ranges require no valid source/destination element address.
  if an == 0 or bn == 0:
    return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  if left <= right: right-left < uint(an) # The lower source address selects its own extent.
  else: left-right < uint(bn) # A lower destination reverses the relevant extent.

# Reject source sequence overlap against the entire destination without overflowing typed record extents.
proc sourceAlias[T](values: openArray[T], output: var openArray[byte],
    size: int): HeaderError {.raises: [].} =
  # Typed stride is checked independently of the wire stride.
  if values.len > high(int) div sizeof(T):
    return HeaderError.LengthOverflow
  # An earlier output field must not corrupt any later source record.
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(T), addr output[0], size):
    return HeaderError.AliasedBuffers
  HeaderError.None

# Validate complete capacity and serialized resource policy before any destination address access.
proc destination(size: int, config: HeaderConfig, output: var openArray[
    byte]): HeaderError {.raises: [].} =
  # Caller byte budget bounds only the selected encoded prefix.
  if uint64(size) > uint64(config.maxBytes):
    return HeaderError.LimitExceeded
  # Require the entire output before its first write.
  if output.len < size:
    return HeaderError.OutputTooSmall
  HeaderError.None

# Commit exact preflighted bytes; no alias, count or policy error remains possible here.
proc put(bytes: openArray[byte], output: var openArray[byte], cursor: var int) {.raises: [].} =
  # Complete operation preflight proved this destination interval before invoking private commit helpers.
  for octet in bytes:
    output[cursor] = octet
    inc cursor

# Commit a fixed E2/E4 scalar without compact-natural substitution or byte narrowing loss.
proc putScalar(value: uint32, width: int, output: var openArray[byte], cursor: var int) {.raises: [].} =
  # Fixed widths always retain little-endian zero/high bytes alike.
  for i in 0..<width:
    output[cursor] = byte((value shr (8*i)) and 255)
    inc cursor

# Commit a bounded natural count's active prefix, never its unused encoder buffer.
proc putNumber(value: int, output: var openArray[byte], cursor: var int) {.raises: [].} =
  let encoded = natural.encode(JamNatural(value))
  put(encoded.bytes.toOpenArray(0, int(encoded.len)-1), output, cursor)

# Commit one fully owned fixed winner record in identifier/E1 attempt order.
proc putTicket(value: WinningTicket, output: var openArray[byte], cursor: var int) {.raises: [].} =
  put(array[32, byte](value.id), output, cursor)
  output[cursor] = byte(value.attempt)
  inc cursor

# Commit a preflighted optional epoch tuple without reordering validators or validating points.
proc putEpoch(value: EpochMarker, output: var openArray[byte], cursor: var int) {.raises: [].} =
  output[cursor] = byte(value.present)
  inc cursor
  # Only a present marker has the two entropy fields and a canonical natural validator count.
  if value.present:
    put(array[32, byte](value.entropy), output, cursor)
    put(array[32, byte](value.ticketsEntropy), output, cursor)
    putNumber(value.validators.len, output, cursor)
    # Index order is semantically significant; repeated/null key encodings remain opaque here.
    for validator in value.validators:
      put(array[32, byte](validator.bandersnatch), output, cursor)
      put(array[32, byte](validator.ed25519), output, cursor)

# Commit a preflighted optional fixed-length winner tuple with no additional count discriminator.
proc putWinners(value: WinnersMarker, output: var openArray[byte], cursor: var int) {.raises: [].} =
  output[cursor] = byte(value.present)
  inc cursor
  # Ticket ordering is the caller's state-derived slot order and must never be sorted here.
  if value.present:
    for ticket in value.tickets: putTicket(ticket, output, cursor) # Every ticket was measured before any write.

# Commit the complete unsigned tuple, including variable offender keys after the entropy proof.
proc putUnsigned(value: UnsignedHeader, output: var openArray[byte], cursor: var int) {.raises: [].} =
  put(array[32, byte](value.parent), output, cursor)
  put(array[32, byte](value.priorState), output, cursor)
  put(array[32, byte](value.extrinsics), output, cursor)
  putScalar(uint32(value.slot), 4, output, cursor)
  putEpoch(value.epoch, output, cursor)
  putWinners(value.winners, output, cursor)
  putScalar(uint16(value.author), 2, output, cursor)
  put(array[96, byte](value.entropyProof), output, cursor)
  putNumber(value.offenders.len, output, cursor)
  # Preserve culprit-key then fault-key concatenation, including any cross-section duplicates.
  for key in value.offenders: put(array[32, byte](key), output, cursor)

# Check all nested source storage against the whole output before commit begins.
proc unsignedAlias(value: UnsignedHeader, output: var openArray[byte],
    size: int): HeaderError {.raises: [].} =
  # Outer fields and optional sequence descriptors must survive all writes.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], size):
    return HeaderError.AliasedBuffers
  # Only present epoch alternatives borrow validator storage that must survive commit.
  if value.epoch.present:
    let error = sourceAlias(value.epoch.validators, output, size)
    # Late validator source storage cannot overlap earlier header fields.
    if error != HeaderError.None:
      return error
  # Only present winner alternatives borrow the configured ticket source sequence.
  if value.winners.present:
    let error = sourceAlias(value.winners.tickets, output, size)
    # Every winner source must be disjoint from the complete written destination.
    if error != HeaderError.None:
      return error
  sourceAlias(value.offenders, output, size)

# Atomically encode a full header after validating every unsigned source field and its final seal extent.
proc encodeHeader*(value: Header, config: HeaderConfig, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  # Invalid chain domains precede source traversal.
  if not validConfig(config):
    return HeaderResult[int](error: HeaderError.InvalidConfig)
  let measured = unsignedSize(value.unsigned, config)
  # A malformed last field must leave every earlier destination byte unchanged.
  if measured.error != HeaderError.None:
    return measured
  var size = measured.value
  let seal = grow(size, 1, 96)
  # Include seal cost before capacity or aliases.
  if seal != HeaderError.None:
    return HeaderResult[int](error: seal)
  let capacity = destination(size, config, output)
  # No output address is used before whole capacity succeeds.
  if capacity != HeaderError.None:
    return HeaderResult[int](error: capacity)
  # Protect fixed seal and outer source storage too.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], size):
    return HeaderResult[int](error: HeaderError.AliasedBuffers)
  let alias = unsignedAlias(value.unsigned, output, size)
  # Cross-field nested aliases reject before writing the parent hash.
  if alias != HeaderError.None:
    return HeaderResult[int](error: alias)
  var cursor = 0
  putUnsigned(value.unsigned, output, cursor)
  put(array[96, byte](value.seal), output, cursor)
  doAssert cursor == size
  HeaderResult[int](error: HeaderError.None, value: size)

# Atomically encode the exact header signing payload, omitting only the final 96-byte seal.
proc encodeUnsignedHeader*(value: UnsignedHeader, config: HeaderConfig, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  # Caller supplies the author population and epoch parameters.
  if not validConfig(config):
    return HeaderResult[int](error: HeaderError.InvalidConfig)
  let measured = unsignedSize(value, config)
  # No source error can authorize a partial signing payload.
  if measured.error != HeaderError.None:
    return measured
  let capacity = destination(measured.value, config, output)
  # Complete signing bytes must fit before addresses or writes.
  if capacity != HeaderError.None:
    return HeaderResult[int](error: capacity)
  let alias = unsignedAlias(value, output, measured.value)
  # Check every nested source against the whole signing destination.
  if alias != HeaderError.None:
    return HeaderResult[int](error: alias)
  var cursor = 0
  putUnsigned(value, output, cursor)
  doAssert cursor == measured.value
  measured

# Encode one standalone optional epoch marker with the same validator-count policy as headers.
proc encodeEpochMarker*(value: EpochMarker, config: HeaderConfig, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  # Default profiles cannot authorize marker access.
  if not validConfig(config):
    return HeaderResult[int](error: HeaderError.InvalidConfig)
  let measured = epochSize(value, config)
  # Valcount policy precedes capacity and writes.
  if measured.error != HeaderError.None:
    return measured
  let capacity = destination(measured.value, config, output)
  # Require the entire optional tuple.
  if capacity != HeaderError.None:
    return HeaderResult[int](error: capacity)
  # Protect fixed entropy and sequence descriptors.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], measured.value):
    return HeaderResult[int](error: HeaderError.AliasedBuffers)
  # A present standalone epoch also borrows all validator pairs for the complete call.
  if value.present:
    let alias = sourceAlias(value.validators, output, measured.value)
    # Complete key storage is checked before writing the optional tag.
    if alias != HeaderError.None:
      return HeaderResult[int](error: alias)
  var cursor = 0
  putEpoch(value, output, cursor)
  measured

# Encode one optional configured-length winner tuple without serializing a count.
proc encodeWinnersMarker*(value: WinnersMarker, config: HeaderConfig, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  # Epoch length must be positive even for absent markers.
  if not validConfig(config):
    return HeaderResult[int](error: HeaderError.InvalidConfig)
  let measured = winnersSize(value, config)
  # Short/long source sequences cannot silently change the epoch parameter.
  if measured.error != HeaderError.None:
    return measured
  let capacity = destination(measured.value, config, output)
  # Whole output extent precedes address access.
  if capacity != HeaderError.None:
    return HeaderResult[int](error: capacity)
  # The optional descriptor is borrowed source storage.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], measured.value):
    return HeaderResult[int](error: HeaderError.AliasedBuffers)
  # A present standalone winner tuple must protect every source record before its tag is written.
  if value.present:
    let alias = sourceAlias(value.tickets, output, measured.value)
    # No earlier ticket can overwrite a later source record.
    if alias != HeaderError.None:
      return HeaderResult[int](error: alias)
  var cursor = 0
  putWinners(value, output, cursor)
  measured

# Encode one owned fixed winning ticket atomically; every E1 attempt byte is structurally representable.
proc encodeWinningTicket*(value: WinningTicket, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  # The identifier and final attempt must both fit.
  if output.len < 33:
    return HeaderResult[int](error: HeaderError.OutputTooSmall)
  # Protect the complete fixed source record.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], 33):
    return HeaderResult[int](error: HeaderError.AliasedBuffers)
  var cursor = 0
  putTicket(value, output, cursor)
  HeaderResult[int](error: HeaderError.None, value: cursor)

# Copy one private retained interval without permitting any write into the owner's complete immutable wire.
proc copy(data: HeaderData, start, size: int, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  # No partially copied owner prefix on insufficient capacity.
  if output.len < size:
    return HeaderResult[int](error: HeaderError.OutputTooSmall)
  # Protect every retained field, not just the selected source interval.
  if overlaps(unsafeAddr data.wire[0], data.wire.len, addr output[0], size):
    return HeaderResult[int](error: HeaderError.AliasedBuffers)
  # All stored intervals were checked against these same private snapshot bytes before capture.
  for i in 0..<size: output[i] = data.wire[start+i]
  HeaderResult[int](error: HeaderError.None, value: size)

# Select an unsigned view retaining its full sealed parent; callers cannot pair it with another buffer.
proc unsignedPart*(owner: OwnedHeader): HeaderResult[OwnedUnsignedHeader] {.raises: [].} =
  # Default handles carry no validated parent.
  if owner.data.isNil:
    return HeaderResult[OwnedUnsignedHeader](error: HeaderError.InvalidOwner)
  HeaderResult[OwnedUnsignedHeader](error: HeaderError.None, value: OwnedUnsignedHeader(
      data: owner.data))

# Copy unsigned fixed metadata and exact signing-prefix length without exposing private offsets.
proc unsignedHeaderInfo*(owner: OwnedUnsignedHeader): HeaderResult[UnsignedHeaderInfo] {.raises: [].} =
  # No fabricated empty header for default handles.
  if owner.data.isNil:
    return HeaderResult[UnsignedHeaderInfo](error: HeaderError.InvalidOwner)
  HeaderResult[UnsignedHeaderInfo](error: HeaderError.None, value: owner.data.layout.unsigned)

# Copy complete full-header metadata; the seal remains a separate nominal value after unsigned consumption.
proc headerInfo*(owner: OwnedHeader): HeaderResult[HeaderInfo] {.raises: [].} =
  # Only a validated full capture carries a seal.
  if owner.data.isNil:
    return HeaderResult[HeaderInfo](error: HeaderError.InvalidOwner)
  let layout = owner.data.layout
  HeaderResult[HeaderInfo](error: HeaderError.None, value: HeaderInfo(unsigned: layout.unsigned,
    seal: HeaderSeal(fixed[96](owner.data.wire, layout.unsigned.consumed)),
        consumed: layout.consumed))

# Retain the parent's exact epoch marker, including initialized absence, without detached coordinates.
proc headerEpoch*(owner: OwnedUnsignedHeader): HeaderResult[OwnedEpochMarker] {.raises: [].} =
  # Missing parent storage cannot create a marker.
  if owner.data.isNil:
    return HeaderResult[OwnedEpochMarker](error: HeaderError.InvalidOwner)
  HeaderResult[OwnedEpochMarker](error: HeaderError.None, value: OwnedEpochMarker(data: owner.data))

# Retain the parent's exact winner marker without exporting mutable ticket storage.
proc headerWinners*(owner: OwnedUnsignedHeader): HeaderResult[OwnedWinnersMarker] {.raises: [].} =
  # Default headers have no validated marker alternative.
  if owner.data.isNil:
    return HeaderResult[OwnedWinnersMarker](error: HeaderError.InvalidOwner)
  HeaderResult[OwnedWinnersMarker](error: HeaderError.None, value: OwnedWinnersMarker(
      data: owner.data))

# Copy epoch entropy/count metadata while preserving the optional marker's tagged alternative.
proc epochMarkerInfo*(owner: OwnedEpochMarker): HeaderResult[EpochMarkerInfo] {.raises: [].} =
  # Distinguish default handles from validated absence.
  if owner.data.isNil:
    return HeaderResult[EpochMarkerInfo](error: HeaderError.InvalidOwner)
  HeaderResult[EpochMarkerInfo](error: HeaderError.None, value: owner.data.layout.epoch)

# Copy winner presence/count metadata without exposing slot-order sequences or snapshot storage.
proc winnersMarkerInfo*(owner: OwnedWinnersMarker): HeaderResult[WinnersMarkerInfo] {.raises: [].} =
  # Only validated captures can describe absence.
  if owner.data.isNil:
    return HeaderResult[WinnersMarkerInfo](error: HeaderError.InvalidOwner)
  HeaderResult[WinnersMarkerInfo](error: HeaderError.None, value: owner.data.layout.winners)

# Copy one indexed validator key pair, bound to the exact retained present epoch marker.
proc epochValidatorAt*(owner: OwnedEpochMarker, index: int): HeaderResult[
    EpochValidator] {.raises: [].} =
  # Default marker storage cannot be indexed.
  if owner.data.isNil:
    return HeaderResult[EpochValidator](error: HeaderError.InvalidOwner)
  let layout = owner.data.layout
  # Absence is not a present empty population.
  if not layout.epoch.present:
    return HeaderResult[EpochValidator](error: HeaderError.InvalidIndex)
  # Bound signed indices before stride arithmetic.
  if index < 0 or index >= layout.epoch.validators:
    return HeaderResult[EpochValidator](error: HeaderError.InvalidIndex)
  let start = layout.validatorStart+64*index
  HeaderResult[EpochValidator](error: HeaderError.None, value: EpochValidator(
    bandersnatch: HeaderBsKey(fixed[32](owner.data.wire, start)),
    ed25519: HeaderEdKey(fixed[32](owner.data.wire, start+32))))

# Copy one slot-ordered winning ticket using its original marker owner only.
proc winningTicketAt*(owner: OwnedWinnersMarker, index: int): HeaderResult[
    WinningTicket] {.raises: [].} =
  # Missing owners contain no configured winner sequence.
  if owner.data.isNil:
    return HeaderResult[WinningTicket](error: HeaderError.InvalidOwner)
  let layout = owner.data.layout
  # An absent marker has no valid ticket index.
  if not layout.winners.present:
    return HeaderResult[WinningTicket](error: HeaderError.InvalidIndex)
  # Signed bounds precede byte coordinates.
  if index < 0 or index >= layout.winners.tickets:
    return HeaderResult[WinningTicket](error: HeaderError.InvalidIndex)
  let start = layout.ticketStart+33*index
  let parsed = decodeWinningTicket(owner.data.wire.toOpenArray(start, start+32))
  doAssert parsed.error == HeaderError.None
  HeaderResult[WinningTicket](error: HeaderError.None, value: parsed.value.value)

# Copy one offender identity without sorting or removing cross-section duplicates.
proc headerOffenderAt*(owner: OwnedUnsignedHeader, index: int): HeaderResult[
    HeaderEdKey] {.raises: [].} =
  # Missing parent handles have no offender sequence.
  if owner.data.isNil:
    return HeaderResult[HeaderEdKey](error: HeaderError.InvalidOwner)
  let layout = owner.data.layout
  # No caller-supplied detached coordinates are accepted.
  if index < 0 or index >= layout.unsigned.offenders:
    return HeaderResult[HeaderEdKey](error: HeaderError.InvalidIndex)
  HeaderResult[HeaderEdKey](error: HeaderError.None,
    value: HeaderEdKey(fixed[32](owner.data.wire, layout.offenderStart+32*index)))

# Re-emit an immutable full header atomically, preserving any unused output suffix.
proc encodeOwnedHeader*(owner: OwnedHeader, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  # Default handles cannot stand in for empty headers.
  if owner.data.isNil:
    return HeaderResult[int](error: HeaderError.InvalidOwner)
  copy(owner.data, 0, owner.data.layout.consumed, output)

# Copy exactly the signing payload from either standalone unsigned or retained full-header storage.
proc encodeOwnedUnsignedHeader*(owner: OwnedUnsignedHeader, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  # No default signing prefix exists.
  if owner.data.isNil:
    return HeaderResult[int](error: HeaderError.InvalidOwner)
  copy(owner.data, 0, owner.data.layout.unsigned.consumed, output)

# Re-emit the owner's epoch marker without requiring a second source buffer or configuration.
proc encodeOwnedEpochMarker*(owner: OwnedEpochMarker, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  # Initialized absence differs from a default owner.
  if owner.data.isNil:
    return HeaderResult[int](error: HeaderError.InvalidOwner)
  copy(owner.data, owner.data.layout.epochStart, owner.data.layout.epochLength, output)

# Re-emit the owner's configured winner marker, retaining the original exact slot order.
proc encodeOwnedWinnersMarker*(owner: OwnedWinnersMarker, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  # Missing storage cannot fabricate an absent marker.
  if owner.data.isNil:
    return HeaderResult[int](error: HeaderError.InvalidOwner)
  copy(owner.data, owner.data.layout.winnersStart, owner.data.layout.winnersLength, output)

# Inspect a complete sealed header without allocation; parent block scans retain no source coordinates.
proc inspectHeader*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    HeaderInfo] {.raises: [].} =
  let scanned = scanHeader(input, config, true)
  # The existing sealed scanner proves every marker, author and final signature extent.
  if scanned.error != HeaderError.None: return HeaderResult[HeaderInfo](error: scanned.error)
  HeaderResult[HeaderInfo](error: HeaderError.None, value: HeaderInfo(
    unsigned: scanned.value.unsigned,
    seal: HeaderSeal(fixed[96](input, scanned.value.unsigned.consumed)),
        consumed: scanned.value.consumed))
