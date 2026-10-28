# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 C.2 header/marker codecs; signatures and state-dependent marker eligibility remain
## external.
##
## Exposes header and marker source types, explicit optional markers, owned codecs and copied
## validator/ticket/offender access.

import std/assertions
import ./natural as codec_natural
import ./bounded as codec_bounded
import ./assurances as codec_assurances
import ./tickets as codec_tickets

type
  HeaderParent* = distinct array[32, byte] ## Parent block identity is distinct from the header's two other commitments.
  PriorStateRoot* = distinct array[32, byte] ## This root commits to the prior state rather than a work-report anchor state.
  ExtrinsicRoot* = distinct array[32, byte] ## Header extrinsic commitment is separate from a work-item's individual input-data hash.
  HeaderSlot* = distinct uint32 ## Header timeslots use E4 and cannot be silently substituted for lookup/report slots.
  AuthorIndex* = distinct uint16 ## Author indices use E2 into the posterior active validator population supplied by context.
  EpochEntropy* = distinct array[32, byte] ## Epoch randomness accumulator encoding is distinct from the ticket-contest randomness.
  TicketsEntropy* = distinct array[32, byte] ## Ticket-contest entropy retains its separate nominal role in an epoch marker.
  HeaderBsKey* = distinct array[32, byte] ## Encoded Bandersnatch validator key; structural decoding does not validate its curve point.
  HeaderEdKey* = distinct array[32, byte] ## Encoded Ed25519 key used in epoch pairs and newly offending validator markers.
  WinningTicketId* = distinct array[32, byte] ## A ticket identifier is an opaque hash, not a RingVRF proof or arbitrary root.
  HeaderEntropyProof* = distinct array[96, byte] ## Full opaque 96-byte entropy-yielding VRF encoding; no verification claim is made here.
  HeaderSeal* = distinct array[96, byte] ## Full opaque 96-byte block seal is nominally distinct from the entropy proof.
  EpochSlots* = distinct uint64 ## Epoch length is an explicit chain parameter; winner sequences have no count on the wire.
  EpochValidator* = object ## One indexed validator pair owns its complete key encodings and preserves validator order.
    bandersnatch*: HeaderBsKey
    ed25519*: HeaderEdKey
  WinningTicket* {.byref.} = object ## Public byref source records keep caller-storage identity stable for preflight alias checks.
                                      ## Winning tickets are fixed owned hash/E1 records; TicketAttempt reuses the existing entry-index domain.
    id*: WinningTicketId
    attempt*: TicketAttempt
  EpochMarker* {.byref.} = object ## Encoder source is absent or contains exactly the two entropies and stable borrowed validator sequence.
    case isPresent: bool
    of true:
      entropyValue: EpochEntropy # Present markers alone contain epoch randomness.
      ticketEntropyValue: TicketsEntropy
      validatorValues: seq[EpochValidator]
    of false:
      discard                    # Absent markers contain no default key sequence or entropy value.
                # Winner sources are absent or borrow exactly the configured epoch's sequence of complete tickets.
  WinnersMarker* {.byref.} = object
    case isPresent: bool
    of true:
      ticketValues: seq[WinningTicket] # Present markers contain no separate encoded count.
    of false:
      discard                          # Absence occupies only its canonical zero discriminator.
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
  Header* {.byref.} = object ## A complete header appends the seal to the entire unsigned serialization, including offender keys.
    unsigned*: UnsignedHeader
    seal*: HeaderSeal
  HeaderConfig* = object ## Core ceiling bounds pending epoch key counts independently of the author's posterior-set ceiling.
    cores*: CoreCount
    authorValidators*: ValidatorCount
    epochSlots*: EpochSlots
    maxBytes*: ByteLimit
  HeaderError* {.pure.} = enum ## Failures/default results never carry a record, owner, length or partial parser cursor.
    Uninitialized, None, InvalidConfig, Truncated, NonCanonical, LimitExceeded,
    InvalidTag, InvalidAuthor, OutputTooSmall, AliasedBuffers, LengthOverflow, InvalidOwner, InvalidIndex
  HeaderResult*[T] = object ## Success must be selected explicitly before reading the complete application value.
    case status: HeaderError
    of None:
      completed: T # Only successful operations publish values or progress.
    else:
      discard      # Rejections carry just their typed reason.
                   # Fixed winning-ticket decoding is allocation-free and reports one exact prefix.
  WinningTicketRead* = object
    value*: WinningTicket
    consumed*: int
  EpochMarkerInfo* = object      ## Copied marker metadata cannot expose or rebind its retained validator storage.
    case isPresent: bool
    of true:
      entropyValue: EpochEntropy # Entropies and count exist only for the present alternative.
      ticketEntropyValue: TicketsEntropy
      validatorCount: int
    of false:
      discard # An absent marker has no validator count to mistake for a present empty population.
                # Copied winner metadata contains only the present sequence length, never a detached byte span.
  WinnersMarkerInfo* = object
    case isPresent: bool
    of true:
      ticketCount: int # This equals the configured epoch length for every retained success.
    of false:
      discard          # No default ticket sequence is published by absence.
                       # Header metadata copies complete fixed fields and scalar marker/sequence information.
  UnsignedHeaderInfo* = object
    parent*: HeaderParent
    priorState*: PriorStateRoot
    extrinsics*: ExtrinsicRoot
    slot*: HeaderSlot
    author*: AuthorIndex
    entropyProof*: HeaderEntropyProof
    offenders*, consumed*: int
  HeaderInfo* = object ## Full metadata contains the exact unsigned prefix and final copied seal in distinct nominal roles.
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
  OwnedHeader* = object ## Full header handles retain private bytes and cannot be constructed from an unsigned-only snapshot.
    data: nil HeaderData
  OwnedUnsignedHeader* = object ## Unsigned handles retain the whole parent snapshot when selected from a sealed header.
    data: nil HeaderData
  OwnedEpochMarker* = object ## Epoch handles retain their original header/standalone marker without exposing coordinates.
    data: nil HeaderData
  OwnedWinnersMarker* = object ## Winner handles retain their original header/standalone marker without exporting mutable tickets.
    data: nil HeaderData
  HeaderRead* = object ## Successful full decoding binds exact consumed progress to its owner.
    owner*: OwnedHeader
    consumed*: int
  UnsignedHeaderRead* = object ## Successful unsigned decoding has its own handle type, distinct from a sealed header.
    owner*: OwnedUnsignedHeader
    consumed*: int
  EpochMarkerRead* = object ## Standalone epoch decoding returns an owner even for a validated absent marker.
    owner*: OwnedEpochMarker
    consumed*: int
  WinnersMarkerRead* = object ## Standalone winner decoding returns an owner even for a validated absent marker.
    owner*: OwnedWinnersMarker
    consumed*: int

func error*[T](value: HeaderResult[T]): HeaderError =
  ## Read generic outcomes without exposing a mutable result discriminator.
  value.status
func value*[T](value: HeaderResult[T]): T {.inline, requires: value.status == HeaderError.None.} =
  ## Only a complete operation publishes values, retained handles or progress.
  value.completed
func headerFailure*[T](reason: HeaderError): HeaderResult[T] {.requires: reason !=
    HeaderError.None.} =
  ## Sibling frame adapters may report failure; the success tag is forbidden without a value.
  HeaderResult[T](status: reason)
func present*(value: EpochMarker): bool =
  ## Encoder source presence is read-only and cannot be retagged independently of its payload.
  value.isPresent
func present*(value: WinnersMarker): bool =
  ## Winner source presence selects whether any ticket storage exists.
  value.isPresent
func present*(value: EpochMarkerInfo): bool =
  ## Copied epoch metadata preserves validated absence independently of default owners.
  value.isPresent
func present*(value: WinnersMarkerInfo): bool =
  ## Copied winner metadata has no sequence length when absent.
  value.isPresent
func entropy*(value: EpochMarker): EpochEntropy {.requires: value.isPresent.} =
  ## Source entropy is copied only from a present marker.
  value.entropyValue
func ticketsEntropy*(value: EpochMarker): TicketsEntropy {.requires: value.isPresent.} =
  ## Source contest entropy retains its distinct nominal domain and requires presence.
  value.ticketEntropyValue
func epochValidatorCopies*(value: EpochMarker): seq[
    EpochValidator] {.requires: value.isPresent.} =
  ## Read-only source access returns a value copy; internal encoders borrow private storage directly.
  value.validatorValues
proc editEpochValidators*(value: var EpochMarker): var seq[
    EpochValidator] {.requires: value.isPresent.} =
  ## Mutable encoder sources retain ordinary sequence editing through a presence-checked borrowed field.
  value.validatorValues
func winnerTicketCopies*(value: WinnersMarker): seq[
    WinningTicket] {.requires: value.isPresent.} =
  ## Read-only winner source access returns a copy, never an immutable snapshot's private storage.
  value.ticketValues
proc editWinnerTickets*(value: var WinnersMarker): var seq[
    WinningTicket] {.requires: value.isPresent.} =
  ## Mutable source ticket edits preserve actual source identity for later alias preflight.
  value.ticketValues
func entropy*(value: EpochMarkerInfo): EpochEntropy {.requires: value.isPresent.} =
  ## Copied epoch entropy exists only in the present metadata alternative.
  value.entropyValue
func ticketsEntropy*(value: EpochMarkerInfo): TicketsEntropy {.requires: value.isPresent.} =
  ## Copied contest entropy requires the same present alternative.
  value.ticketEntropyValue
func validators*(value: EpochMarkerInfo): int {.requires: value.isPresent.} =
  ## Only present metadata exposes a validator cardinality.
  value.validatorCount
func tickets*(value: WinnersMarkerInfo): int {.requires: value.isPresent.} =
  ## Only present metadata exposes a configured ticket count.
  value.ticketCount
func absentEpoch*(): EpochMarker =
  ## Absent epoch sources contain no entropy or validator sequence.
  default(EpochMarker)
func presentEpoch*(entropy: EpochEntropy, ticketsEntropy: TicketsEntropy, validators: seq[
    EpochValidator]): EpochMarker =
  ## Construct a present borrowed source; configuration/cardinality policy remains encoder preflight.
  EpochMarker(isPresent: true, entropyValue: entropy, ticketEntropyValue: ticketsEntropy,
      validatorValues: validators)
func absentWinners*(): WinnersMarker =
  ## An absent winner source contains no default ticket sequence.
  default(WinnersMarker)
func presentWinners*(tickets: seq[WinningTicket]): WinnersMarker =
  ## Construct a present winner source; exact configured epoch length is checked before encoding.
  WinnersMarker(isPresent: true, ticketValues: tickets)

proc fullHeaderConfig*(maxBytes: ByteLimit): HeaderConfig {.raises: [].} =
  ## Full-profile convenience leaves the serialized byte budget an explicit caller resource decision.
  HeaderConfig(cores: CoreCount(341), authorValidators: ValidatorCount(1023),
    epochSlots: EpochSlots(600), maxBytes: maxBytes)

# Validate GP validator domains and a positive epoch length before any untrusted byte or source access.
proc validConfig(config: HeaderConfig): bool {.raises: [].} =
  codec_assurances.validConfig(AssuranceConfig(cores: config.cores,
      validators: config.authorValidators)) and
    uint64(config.epochSlots) > 0

# Copy an exact owned identity/proof after its enclosing input extent has been checked.
proc fixed[N: static[int]](input: openArray[byte], start: int): array[N, byte] {.raises: [].} =
  result = default(array[N, byte])
  # No caller pointer escapes these exact value copies.
  for i in 0..<N: result[i] = input[start+i]

# Decode only previously proved E2/E4 fields in little-endian order.
proc scalar(input: openArray[byte], start, width: int): uint32 {.raises: [].} =
  result = 0
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
  let parsed = codec_natural.decode(input.toOpenArray(cursor, input.high))
  # Preserve truncated versus overlong framing before interpreting a count.
  if not parsed.ok:
    return HeaderResult[int](status: if parsed.error ==
        codec_natural.truncated: HeaderError.Truncated
      else: HeaderError.NonCanonical) # An overlong discriminator cannot select another valid wire representation.
  cursor += int(parsed.consumed)
  # Every caller's count ceiling is at most 1023, so checking it also proves host narrowing.
  if uint64(cursor) > uint64(config.maxBytes) or uint64(parsed.value) > ceiling:
    return HeaderResult[int](status: HeaderError.LimitExceeded)
  HeaderResult[int](status: HeaderError.None, completed: int(uint64(parsed.value)))

# Read a canonical optional marker discriminator without allocating or accepting other octet tags.
proc tag(input: openArray[byte], cursor: var int, config: HeaderConfig): HeaderResult[
    bool] {.raises: [].} =
  let checked = extent(input, cursor, 1, 1, config)
  # Input/budget checks precede the first discriminator byte access.
  if checked != HeaderError.None:
    return HeaderResult[bool](status: checked)
  let value = input[cursor]
  # Only canonical absent/present alternatives exist.
  if value > 1:
    return HeaderResult[bool](status: HeaderError.InvalidTag)
  inc cursor
  HeaderResult[bool](status: HeaderError.None, completed: value == 1)

# Scan a complete epoch marker into bounded metadata; key order/encodings remain opaque at this layer.
proc scanEpoch(input: openArray[byte], cursor: var int, config: HeaderConfig,
    layout: var Layout): HeaderError {.raises: [].} =
  layout.epochStart = cursor
  let present = tag(input, cursor, config)
  # A missing/invalid marker never publishes default entropy or validator metadata.
  if present.error != HeaderError.None:
    return present.error
  layout.epoch = default(EpochMarkerInfo)
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
    layout.epoch = EpochMarkerInfo(isPresent: true, entropyValue: entropy,
      ticketEntropyValue: ticketsEntropy, validatorCount: count.value)
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
  layout.winners = default(WinnersMarkerInfo)
  # Every fixed 33-byte ticket must be available before converting the configured count to host int.
  if present.value:
    let checked = extent(input, cursor, uint64(config.epochSlots), 33, config)
    # Huge positive configurations fail without arithmetic overflow or allocation.
    if checked != HeaderError.None:
      return checked
    layout.ticketStart = cursor
    layout.winners = WinnersMarkerInfo(isPresent: true, ticketCount: int(uint64(config.epochSlots)))
    cursor += layout.winners.tickets*33
  layout.winnersLength = cursor-layout.winnersStart
  HeaderError.None

# Scan one unsigned/full header without input-derived allocation or mutable caller writes.
proc scanHeader(input: openArray[byte], config: HeaderConfig, sealed: bool): HeaderResult[
    Layout] {.raises: [].} =
  # Configuration determines structural author/epoch domains and cannot be inferred from input.
  if not validConfig(config):
    return HeaderResult[Layout](status: HeaderError.InvalidConfig)
  var layout: Layout = default(Layout)
  var cursor = 0
  let prefix = extent(input, cursor, 1, 100, config)
  # Three hashes and fixed E4 slot form the complete prefix.
  if prefix != HeaderError.None:
    return HeaderResult[Layout](status: prefix)
  layout.unsigned.parent = HeaderParent(fixed[32](input, 0))
  layout.unsigned.priorState = PriorStateRoot(fixed[32](input, 32))
  layout.unsigned.extrinsics = ExtrinsicRoot(fixed[32](input, 64))
  layout.unsigned.slot = HeaderSlot(scalar(input, 96, 4))
  cursor = 100
  let epoch = scanEpoch(input, cursor, config, layout)
  # Epoch failure discards the complete header scan.
  if epoch != HeaderError.None:
    return HeaderResult[Layout](status: epoch)
  let winners = scanWinners(input, cursor, config, layout)
  # No guessed count or marker length is used.
  if winners != HeaderError.None:
    return HeaderResult[Layout](status: winners)
  let credentials = extent(input, cursor, 1, 98, config)
  # Complete E2 author and entropy proof are required.
  if credentials != HeaderError.None:
    return HeaderResult[Layout](status: credentials)
  let author = scalar(input, cursor, 2)
  # E2 representability alone is not author-domain membership.
  if uint64(author) >= uint64(config.authorValidators):
    return HeaderResult[Layout](status: HeaderError.InvalidAuthor)
  layout.unsigned.author = AuthorIndex(author)
  layout.unsigned.entropyProof = HeaderEntropyProof(fixed[96](input, cursor+2))
  cursor += 98
  let count = number(input, cursor, 32, config)
  # At most sixteen culprit plus sixteen fault keys are possible.
  if count.error != HeaderError.None:
    return HeaderResult[Layout](status: count.error)
  let offenders = extent(input, cursor, uint64(count.value), 32, config)
  # Offender order and cross-section duplicates are preserved exactly.
  if offenders != HeaderError.None:
    return HeaderResult[Layout](status: offenders)
  layout.offenderStart = cursor
  layout.unsigned.offenders = count.value
  cursor += count.value*32
  layout.unsigned.consumed = cursor
  # A full header appends the complete opaque seal after all unsigned fields, including offenders.
  if sealed:
    let seal = extent(input, cursor, 1, 96, config)
    # A truncated final seal cannot expose an unsigned success as a full header.
    if seal != HeaderError.None:
      return HeaderResult[Layout](status: seal)
    cursor += 96
  layout.consumed = cursor
  HeaderResult[Layout](status: HeaderError.None, completed: layout)

# Capture only a completely scanned prefix in private immutable acyclic ARC storage.
proc capture(input: openArray[byte], layout: Layout): HeaderData {.raises: [].} =
  result = HeaderData(layout: layout, wire: newSeq[byte](layout.consumed))
  # Exclude unrelated trailing bytes from the snapshot and its resource accounting.
  for i in 0..<result.wire.len: result.wire[i] = input[i]

proc decodeHeader*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    HeaderRead] {.raises: [].} =
  ## Decode a full header only after all framing, counts, author policy and final seal bytes validate.
  let scanned = scanHeader(input, config, true)
  # No attacker-derived allocation occurs for failed/default results.
  if scanned.error != HeaderError.None:
    return HeaderResult[HeaderRead](status: scanned.error)
  HeaderResult[HeaderRead](status: HeaderError.None, completed: HeaderRead(
    owner: OwnedHeader(data: capture(input, scanned.value)), consumed: scanned.value.consumed))

proc decodeUnsignedHeader*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    UnsignedHeaderRead] {.raises: [].} =
  ## Decode an unsigned header as its own prefix/owner type; no seal is required or guessed.
  let scanned = scanHeader(input, config, false)
  # Every failed scan discards its private marker coordinates and progress.
  if scanned.error != HeaderError.None:
    return HeaderResult[UnsignedHeaderRead](status: scanned.error)
  HeaderResult[UnsignedHeaderRead](status: HeaderError.None, completed: UnsignedHeaderRead(
    owner: OwnedUnsignedHeader(data: capture(input, scanned.value)),
        consumed: scanned.value.consumed))

proc decodeEpochMarker*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    EpochMarkerRead] {.raises: [].} =
  ## Decode a standalone epoch marker, preserving initialized absence separately from a default owner.
  # Reject invalid chain domains before input access.
  if not validConfig(config):
    return HeaderResult[EpochMarkerRead](status: HeaderError.InvalidConfig)
  var layout: Layout = default(Layout)
  var cursor = 0
  let error = scanEpoch(input, cursor, config, layout)
  # No partial entropy/key owner is published.
  if error != HeaderError.None:
    return HeaderResult[EpochMarkerRead](status: error)
  layout.consumed = cursor
  HeaderResult[EpochMarkerRead](status: HeaderError.None, completed: EpochMarkerRead(
    owner: OwnedEpochMarker(data: capture(input, layout)), consumed: cursor))

proc decodeWinnersMarker*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    WinnersMarkerRead] {.raises: [].} =
  ## Decode standalone winners using the caller's epoch length rather than a nonexistent sequence count.
  # Require explicit valid chain configuration first.
  if not validConfig(config):
    return HeaderResult[WinnersMarkerRead](status: HeaderError.InvalidConfig)
  var layout: Layout = default(Layout)
  var cursor = 0
  let error = scanWinners(input, cursor, config, layout)
  # Fixed ticket extents must all validate before capture.
  if error != HeaderError.None:
    return HeaderResult[WinnersMarkerRead](status: error)
  layout.consumed = cursor
  HeaderResult[WinnersMarkerRead](status: HeaderError.None, completed: WinnersMarkerRead(
    owner: OwnedWinnersMarker(data: capture(input, layout)), consumed: cursor))

proc decodeWinningTicket*(input: openArray[byte]): HeaderResult[WinningTicketRead] {.raises: [].} =
  ## Fixed winner-ticket decoding owns every identifier/attempt byte and needs no chain configuration.
  # Identifier and E1 attempt must both exist.
  if input.len < 33:
    return HeaderResult[WinningTicketRead](status: HeaderError.Truncated)
  HeaderResult[WinningTicketRead](status: HeaderError.None, completed: WinningTicketRead(
    consumed: 33,
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
    let count = value.validatorValues.len
    # Pending population follows valcount, independently of author population.
    if count < 6 or uint64(count) > 3*uint64(config.cores) or count mod 3 != 0:
      return HeaderResult[int](status: HeaderError.LimitExceeded)
    size += 64+int(codec_natural.encode(JamNatural(count)).len)+64*count
  HeaderResult[int](status: HeaderError.None, completed: size)

# Measure winners with exact caller epoch cardinality and safe host arithmetic.
proc winnersSize(value: WinnersMarker, config: HeaderConfig): HeaderResult[int] {.raises: [].} =
  var size = 1
  # Present winners are fixed-length tuples, never a variable-count sequence.
  if value.present:
    # An encoder must not silently add/drop epoch tickets.
    if uint64(value.ticketValues.len) != uint64(config.epochSlots):
      return HeaderResult[int](status: HeaderError.LimitExceeded)
    let error = grow(size, value.ticketValues.len, 33)
    # Host extent must be representable before capacity checks.
    if error != HeaderError.None:
      return HeaderResult[int](status: error)
  HeaderResult[int](status: HeaderError.None, completed: size)

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
    return HeaderResult[int](status: HeaderError.InvalidAuthor)
  # Judgments derive at most 16+16 new offender entries.
  if value.offenders.len > 32:
    return HeaderResult[int](status: HeaderError.LimitExceeded)
  var size = 198+epoch.value
  let winnerGrowth = grow(size, winners.value, 1)
  # A complete winner tuple can be large under custom epoch parameters.
  if winnerGrowth != HeaderError.None:
    return HeaderResult[int](status: winnerGrowth)
  let suffix = int(codec_natural.encode(JamNatural(value.offenders.len)).len)+32*value.offenders.len
  let suffixGrowth = grow(size, suffix, 1)
  # Complete offender count/keys must fit after winners.
  if suffixGrowth != HeaderError.None:
    return HeaderResult[int](status: suffixGrowth)
  HeaderResult[int](status: HeaderError.None, completed: size)

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
  let encoded = codec_natural.encode(JamNatural(value))
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
    putNumber(value.validatorValues.len, output, cursor)
    # Index order is semantically significant; repeated/null key encodings remain opaque here.
    for validator in value.validatorValues:
      put(array[32, byte](validator.bandersnatch), output, cursor)
      put(array[32, byte](validator.ed25519), output, cursor)

# Commit a preflighted optional fixed-length winner tuple with no additional count discriminator.
proc putWinners(value: WinnersMarker, output: var openArray[byte], cursor: var int) {.raises: [].} =
  output[cursor] = byte(value.present)
  inc cursor
  # Ticket ordering is the caller's state-derived slot order and must never be sorted here.
  if value.present:
    for ticket in value.ticketValues: putTicket(ticket, output,
        cursor) # Every ticket was measured before any write.

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
    let error = sourceAlias(value.epoch.validatorValues, output, size)
    # Late validator source storage cannot overlap earlier header fields.
    if error != HeaderError.None:
      return error
  # Only present winner alternatives borrow the configured ticket source sequence.
  if value.winners.present:
    let error = sourceAlias(value.winners.ticketValues, output, size)
    # Every winner source must be disjoint from the complete written destination.
    if error != HeaderError.None:
      return error
  sourceAlias(value.offenders, output, size)

proc encodeHeader*(value: Header, config: HeaderConfig, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  ## Atomically encode a full header after validating every unsigned source field and its final seal extent.
  # Invalid chain domains precede source traversal.
  if not validConfig(config):
    return HeaderResult[int](status: HeaderError.InvalidConfig)
  let measured = unsignedSize(value.unsigned, config)
  # A malformed last field must leave every earlier destination byte unchanged.
  if measured.error != HeaderError.None:
    return measured
  var size = measured.value
  let seal = grow(size, 1, 96)
  # Include seal cost before capacity or aliases.
  if seal != HeaderError.None:
    return HeaderResult[int](status: seal)
  let capacity = destination(size, config, output)
  # No output address is used before whole capacity succeeds.
  if capacity != HeaderError.None:
    return HeaderResult[int](status: capacity)
  # Protect fixed seal and outer source storage too.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], size):
    return HeaderResult[int](status: HeaderError.AliasedBuffers)
  let alias = unsignedAlias(value.unsigned, output, size)
  # Cross-field nested aliases reject before writing the parent hash.
  if alias != HeaderError.None:
    return HeaderResult[int](status: alias)
  var cursor = 0
  putUnsigned(value.unsigned, output, cursor)
  put(array[96, byte](value.seal), output, cursor)
  assert cursor == size
  HeaderResult[int](status: HeaderError.None, completed: size)

proc encodeUnsignedHeader*(value: UnsignedHeader, config: HeaderConfig, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  ## Atomically encode the exact header signing payload, omitting only the final 96-byte seal.
  # Caller supplies the author population and epoch parameters.
  if not validConfig(config):
    return HeaderResult[int](status: HeaderError.InvalidConfig)
  let measured = unsignedSize(value, config)
  # No source error can authorize a partial signing payload.
  if measured.error != HeaderError.None:
    return measured
  let capacity = destination(measured.value, config, output)
  # Complete signing bytes must fit before addresses or writes.
  if capacity != HeaderError.None:
    return HeaderResult[int](status: capacity)
  let alias = unsignedAlias(value, output, measured.value)
  # Check every nested source against the whole signing destination.
  if alias != HeaderError.None:
    return HeaderResult[int](status: alias)
  var cursor = 0
  putUnsigned(value, output, cursor)
  assert cursor == measured.value
  measured

proc encodeEpochMarker*(value: EpochMarker, config: HeaderConfig, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  ## Encode one standalone optional epoch marker with the same validator-count policy as headers.
  # Default profiles cannot authorize marker access.
  if not validConfig(config):
    return HeaderResult[int](status: HeaderError.InvalidConfig)
  let measured = epochSize(value, config)
  # Valcount policy precedes capacity and writes.
  if measured.error != HeaderError.None:
    return measured
  let capacity = destination(measured.value, config, output)
  # Require the entire optional tuple.
  if capacity != HeaderError.None:
    return HeaderResult[int](status: capacity)
  # Protect fixed entropy and sequence descriptors.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], measured.value):
    return HeaderResult[int](status: HeaderError.AliasedBuffers)
  # A present standalone epoch also borrows all validator pairs for the complete call.
  if value.present:
    let alias = sourceAlias(value.validatorValues, output, measured.value)
    # Complete key storage is checked before writing the optional tag.
    if alias != HeaderError.None:
      return HeaderResult[int](status: alias)
  var cursor = 0
  putEpoch(value, output, cursor)
  measured

proc encodeWinnersMarker*(value: WinnersMarker, config: HeaderConfig, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  ## Encode one optional configured-length winner tuple without serializing a count.
  # Epoch length must be positive even for absent markers.
  if not validConfig(config):
    return HeaderResult[int](status: HeaderError.InvalidConfig)
  let measured = winnersSize(value, config)
  # Short/long source sequences cannot silently change the epoch parameter.
  if measured.error != HeaderError.None:
    return measured
  let capacity = destination(measured.value, config, output)
  # Whole output extent precedes address access.
  if capacity != HeaderError.None:
    return HeaderResult[int](status: capacity)
  # The optional descriptor is borrowed source storage.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], measured.value):
    return HeaderResult[int](status: HeaderError.AliasedBuffers)
  # A present standalone winner tuple must protect every source record before its tag is written.
  if value.present:
    let alias = sourceAlias(value.ticketValues, output, measured.value)
    # No earlier ticket can overwrite a later source record.
    if alias != HeaderError.None:
      return HeaderResult[int](status: alias)
  var cursor = 0
  putWinners(value, output, cursor)
  measured

proc encodeWinningTicket*(value: WinningTicket, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  ## Encode one owned fixed winning ticket atomically; every E1 attempt byte is structurally representable.
  # The identifier and final attempt must both fit.
  if output.len < 33:
    return HeaderResult[int](status: HeaderError.OutputTooSmall)
  # Protect the complete fixed source record.
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], 33):
    return HeaderResult[int](status: HeaderError.AliasedBuffers)
  var cursor = 0
  putTicket(value, output, cursor)
  HeaderResult[int](status: HeaderError.None, completed: cursor)

# Copy one private retained interval without permitting any write into the owner's complete immutable wire.
proc copy(data: HeaderData, start, size: int, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  # No partially copied owner prefix on insufficient capacity.
  if output.len < size:
    return HeaderResult[int](status: HeaderError.OutputTooSmall)
  # Protect every retained field, not just the selected source interval.
  if overlaps(unsafeAddr data.wire[0], data.wire.len, addr output[0], size):
    return HeaderResult[int](status: HeaderError.AliasedBuffers)
  # All stored intervals were checked against these same private snapshot bytes before capture.
  for i in 0..<size: output[i] = data.wire[start+i]
  HeaderResult[int](status: HeaderError.None, completed: size)

proc unsignedPart*(owner: OwnedHeader): HeaderResult[OwnedUnsignedHeader] {.raises: [].} =
  ## Select an unsigned view retaining its full sealed parent; callers cannot pair it with another buffer.
  # Default handles carry no validated parent.
  let data = owner.data
  if data == nil:
    return HeaderResult[OwnedUnsignedHeader](status: HeaderError.InvalidOwner)
  HeaderResult[OwnedUnsignedHeader](status: HeaderError.None, completed: OwnedUnsignedHeader(
      data: data))

proc unsignedHeaderInfo*(owner: OwnedUnsignedHeader): HeaderResult[UnsignedHeaderInfo] {.raises: [].} =
  ## Copy unsigned fixed metadata and exact signing-prefix length without exposing private offsets.
  # No fabricated empty header for default handles.
  let data = owner.data
  if data == nil:
    return HeaderResult[UnsignedHeaderInfo](status: HeaderError.InvalidOwner)
  HeaderResult[UnsignedHeaderInfo](status: HeaderError.None, completed: data.layout.unsigned)

proc headerInfo*(owner: OwnedHeader): HeaderResult[HeaderInfo] {.raises: [].} =
  ## Copy complete full-header metadata; the seal remains a separate nominal value after unsigned consumption.
  # Only a validated full capture carries a seal.
  let data = owner.data
  if data == nil:
    return HeaderResult[HeaderInfo](status: HeaderError.InvalidOwner)
  let layout = data.layout
  HeaderResult[HeaderInfo](status: HeaderError.None, completed: HeaderInfo(
    unsigned: layout.unsigned,
    seal: HeaderSeal(fixed[96](data.wire, layout.unsigned.consumed)),
        consumed: layout.consumed))

proc headerEpoch*(owner: OwnedUnsignedHeader): HeaderResult[OwnedEpochMarker] {.raises: [].} =
  ## Retain the parent's exact epoch marker, including initialized absence, without detached coordinates.
  # Missing parent storage cannot create a marker.
  let data = owner.data
  if data == nil:
    return HeaderResult[OwnedEpochMarker](status: HeaderError.InvalidOwner)
  HeaderResult[OwnedEpochMarker](status: HeaderError.None, completed: OwnedEpochMarker(data: data))

proc headerWinners*(owner: OwnedUnsignedHeader): HeaderResult[OwnedWinnersMarker] {.raises: [].} =
  ## Retain the parent's exact winner marker without exporting mutable ticket storage.
  # Default headers have no validated marker alternative.
  let data = owner.data
  if data == nil:
    return HeaderResult[OwnedWinnersMarker](status: HeaderError.InvalidOwner)
  HeaderResult[OwnedWinnersMarker](status: HeaderError.None, completed: OwnedWinnersMarker(
      data: data))

proc epochMarkerInfo*(owner: OwnedEpochMarker): HeaderResult[EpochMarkerInfo] {.raises: [].} =
  ## Copy epoch entropy/count metadata while preserving the optional marker's tagged alternative.
  # Distinguish default handles from validated absence.
  let data = owner.data
  if data == nil:
    return HeaderResult[EpochMarkerInfo](status: HeaderError.InvalidOwner)
  HeaderResult[EpochMarkerInfo](status: HeaderError.None, completed: data.layout.epoch)

proc winnersMarkerInfo*(owner: OwnedWinnersMarker): HeaderResult[WinnersMarkerInfo] {.raises: [].} =
  ## Copy winner presence/count metadata without exposing slot-order sequences or snapshot storage.
  # Only validated captures can describe absence.
  let data = owner.data
  if data == nil:
    return HeaderResult[WinnersMarkerInfo](status: HeaderError.InvalidOwner)
  HeaderResult[WinnersMarkerInfo](status: HeaderError.None, completed: data.layout.winners)

proc epochValidatorAt*(owner: OwnedEpochMarker, index: int): HeaderResult[
    EpochValidator] {.raises: [].} =
  ## Copy one indexed validator key pair, bound to the exact retained present epoch marker.
  # Default marker storage cannot be indexed.
  let data = owner.data
  if data == nil:
    return HeaderResult[EpochValidator](status: HeaderError.InvalidOwner)
  let layout = data.layout
  # Absence is not a present empty population.
  if not layout.epoch.present:
    return HeaderResult[EpochValidator](status: HeaderError.InvalidIndex)
  # Bound signed indices before stride arithmetic.
  if index < 0 or index >= layout.epoch.validators:
    return HeaderResult[EpochValidator](status: HeaderError.InvalidIndex)
  let start = layout.validatorStart+64*index
  HeaderResult[EpochValidator](status: HeaderError.None, completed: EpochValidator(
    bandersnatch: HeaderBsKey(fixed[32](data.wire, start)),
    ed25519: HeaderEdKey(fixed[32](data.wire, start+32))))

proc winningTicketAt*(owner: OwnedWinnersMarker, index: int): HeaderResult[
    WinningTicket] {.raises: [].} =
  ## Copy one slot-ordered winning ticket using its original marker owner only.
  # Missing owners contain no configured winner sequence.
  let data = owner.data
  if data == nil:
    return HeaderResult[WinningTicket](status: HeaderError.InvalidOwner)
  let layout = data.layout
  # An absent marker has no valid ticket index.
  if not layout.winners.present:
    return HeaderResult[WinningTicket](status: HeaderError.InvalidIndex)
  # Signed bounds precede byte coordinates.
  if index < 0 or index >= layout.winners.tickets:
    return HeaderResult[WinningTicket](status: HeaderError.InvalidIndex)
  let start = layout.ticketStart+33*index
  let parsed = decodeWinningTicket(data.wire.toOpenArray(start, start+32))
  assert parsed.error == HeaderError.None
  HeaderResult[WinningTicket](status: HeaderError.None, completed: parsed.value.value)

proc headerOffenderAt*(owner: OwnedUnsignedHeader, index: int): HeaderResult[
    HeaderEdKey] {.raises: [].} =
  ## Copy one offender identity without sorting or removing cross-section duplicates.
  # Missing parent handles have no offender sequence.
  let data = owner.data
  if data == nil:
    return HeaderResult[HeaderEdKey](status: HeaderError.InvalidOwner)
  let layout = data.layout
  # No caller-supplied detached coordinates are accepted.
  if index < 0 or index >= layout.unsigned.offenders:
    return HeaderResult[HeaderEdKey](status: HeaderError.InvalidIndex)
  HeaderResult[HeaderEdKey](status: HeaderError.None,
    completed: HeaderEdKey(fixed[32](data.wire, layout.offenderStart+32*index)))

proc encodeOwnedHeader*(owner: OwnedHeader, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  ## Re-emit an immutable full header atomically, preserving any unused output suffix.
  # Default handles cannot stand in for empty headers.
  let data = owner.data
  if data == nil:
    return HeaderResult[int](status: HeaderError.InvalidOwner)
  copy(data, 0, data.layout.consumed, output)

proc encodeOwnedUnsignedHeader*(owner: OwnedUnsignedHeader, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  ## Copy exactly the signing payload from either standalone unsigned or retained full-header storage.
  # No default signing prefix exists.
  let data = owner.data
  if data == nil:
    return HeaderResult[int](status: HeaderError.InvalidOwner)
  copy(data, 0, data.layout.unsigned.consumed, output)

proc encodeOwnedEpochMarker*(owner: OwnedEpochMarker, output: var openArray[byte]): HeaderResult[
    int] {.raises: [].} =
  ## Re-emit the owner's epoch marker without requiring a second source buffer or configuration.
  # Initialized absence differs from a default owner.
  let data = owner.data
  if data == nil:
    return HeaderResult[int](status: HeaderError.InvalidOwner)
  copy(data, data.layout.epochStart, data.layout.epochLength, output)

proc encodeOwnedWinnersMarker*(owner: OwnedWinnersMarker, output: var openArray[
    byte]): HeaderResult[int] {.raises: [].} =
  ## Re-emit the owner's configured winner marker, retaining the original exact slot order.
  # Missing storage cannot fabricate an absent marker.
  let data = owner.data
  if data == nil:
    return HeaderResult[int](status: HeaderError.InvalidOwner)
  copy(data, data.layout.winnersStart, data.layout.winnersLength, output)

proc inspectHeader*(input: openArray[byte], config: HeaderConfig): HeaderResult[
    HeaderInfo] {.raises: [].} =
  ## Inspect a complete sealed header without allocation; parent block scans retain no source coordinates.
  let scanned = scanHeader(input, config, true)
  # The existing sealed scanner proves every marker, author and final signature extent.
  if scanned.error != HeaderError.None: return HeaderResult[HeaderInfo](status: scanned.error)
  HeaderResult[HeaderInfo](status: HeaderError.None, completed: HeaderInfo(
    unsigned: scanned.value.unsigned,
    seal: HeaderSeal(fixed[96](input, scanned.value.unsigned.consumed)),
        consumed: scanned.value.consumed))
