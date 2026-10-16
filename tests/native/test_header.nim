## Native full/unsigned/marker ownership, lifetime, atomicity, alias and guarded-alternative regressions.
import ../../src/codec/[header, bounded, assurances, tickets]

# Expected-success paths select the result branch before accessing complete values/progress.
proc checked[T](parsed: HeaderResult[T]): T =
  doAssert parsed.error == HeaderError.None
  parsed.value

# Fixed public fixture bytes make identity/proof roles visible without a crypto dependency.
proc bytes[N: static int](value: byte): array[N, byte] =
  # Every fixed field owns its exact bytes and no source pointer survives.
  for i in 0..<N: result[i] = value

# A coherent two-marker source keeps validator order, E1 attempts and unsorted duplicate offenders explicit.
proc sample(): Header =
  result.unsigned.parent = HeaderParent(bytes[32](1))
  result.unsigned.priorState = PriorStateRoot(bytes[32](2))
  result.unsigned.extrinsics = ExtrinsicRoot(bytes[32](3))
  result.unsigned.slot = HeaderSlot(0x12345678)
  result.unsigned.author = AuthorIndex(5)
  result.unsigned.entropyProof = HeaderEntropyProof(bytes[96](77))
  result.seal = HeaderSeal(bytes[96](99))
  result.unsigned.epoch = EpochMarker(present: true, entropy: EpochEntropy(bytes[32](4)),
    ticketsEntropy: TicketsEntropy(bytes[32](5)), validators: newSeq[EpochValidator](6))
  # Reversed key identities preserve their validator-index ordering rather than becoming a set.
  for i in 0..<6:
    result.unsigned.epoch.validators[i].bandersnatch = HeaderBsKey(bytes[32](byte(10-i)))
    result.unsigned.epoch.validators[i].ed25519 = HeaderEdKey(bytes[32](byte(20-i)))
  result.unsigned.winners = WinnersMarker(present: true, tickets: newSeq[WinningTicket](12))
  # Full E1 values remain exactly one attempt octet even above compact-natural boundaries.
  for i in 0..<12:
    result.unsigned.winners.tickets[i] = WinningTicket(id: WinningTicketId(bytes[32](byte(30-i))),
        attempt: TicketAttempt(255-i))
  result.unsigned.offenders = @[HeaderEdKey(bytes[32](8)), HeaderEdKey(bytes[32](7)), HeaderEdKey(
      bytes[32](8))]

let config = HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
  epochSlots: EpochSlots(12), maxBytes: ByteLimit(1024*1024))
var value = sample()
var output: array[4096, byte]
let size = checked(encodeHeader(value, config, output))
let decoded = checked(decodeHeader(output.toOpenArray(0, size-1), config))
let info = checked(headerInfo(decoded.owner))
doAssert info.consumed == size and info.unsigned.consumed+96 == size
let unsigned = checked(unsignedPart(decoded.owner))
var signing: array[4096, byte]
let signingSize = checked(encodeOwnedUnsignedHeader(unsigned, signing))
doAssert signingSize == size-96
# Signing payload retains both markers, entropy proof and offender keys, omitting only the final seal.
for i in 0..<signingSize: doAssert signing[i] == output[i]
for i in 0..<96: doAssert output[signingSize+i] == 99 # Seal bytes occur last, not before offenders.
doAssert checked(decodeUnsignedHeader(output.toOpenArray(0, size-1), config)).consumed == signingSize
doAssert decodeHeader(output.toOpenArray(0, signingSize-1), config).error == HeaderError.Truncated
# Retained fixed metadata and nested owners survive mutation of every original input byte and typed source.
for i in 0..<output.len: output[i] = 0
value.unsigned.winners.tickets[0].attempt = TicketAttempt(0)
doAssert uint8(checked(winningTicketAt(checked(headerWinners(unsigned)), 0)).attempt) == 255

# Return only retained views after explicitly releasing the full parent and destroying caller bytes.
proc retainViews(config: HeaderConfig): tuple[unsigned: OwnedUnsignedHeader,
    epoch: OwnedEpochMarker, winners: OwnedWinnersMarker] =
  var wire: array[4096, byte]
  let count = checked(encodeHeader(sample(), config, wire))
  var parent = checked(decodeHeader(wire.toOpenArray(0, count-1), config)).owner
  result.unsigned = checked(unsignedPart(parent))
  result.epoch = checked(headerEpoch(result.unsigned))
  result.winners = checked(headerWinners(result.unsigned))
  parent = OwnedHeader()
  # ARC child references retain the private parent snapshot after source stack storage disappears.
  for i in 0..<wire.len: wire[i] = 0

var retained = retainViews(config)
doAssert uint32(checked(unsignedHeaderInfo(retained.unsigned)).slot) == 0x12345678
retained.unsigned = OwnedUnsignedHeader()
doAssert array[32, byte](checked(epochValidatorAt(retained.epoch, 0)).ed25519) == bytes[32](20)
doAssert uint8(checked(winningTicketAt(retained.winners, 0)).attempt) == 255
# Child re-emission must use its own exact original marker interval inside the retained full header.
value = sample()
var marker: array[2048, byte]
let epochSize = checked(encodeEpochMarker(value.unsigned.epoch, config, marker))
for i in 0..<output.len: output[i] = 0xA5 # Track the complete unused destination suffix too.
doAssert checked(encodeOwnedEpochMarker(retained.epoch, output)) == epochSize
for i in 0..<epochSize: doAssert output[i] == marker[i] # Entropies/count/indexed key bytes agree.
for i in epochSize..<output.len: doAssert output[i] ==
    0xA5 # Owner extraction never writes unrelated capacity.
let winnersSize = checked(encodeWinnersMarker(value.unsigned.winners, config, marker))
doAssert checked(encodeOwnedWinnersMarker(retained.winners, output)) == winnersSize
for i in 0..<winnersSize: doAssert output[i] == marker[i] # Fixed tuple has no extra count octet.
# Missing handles cannot manufacture validated absence, unsigned prefixes, child markers or proofs.
var absent: OwnedHeader
var absentUnsigned: OwnedUnsignedHeader
var absentEpoch: OwnedEpochMarker
var absentWinners: OwnedWinnersMarker
doAssert headerInfo(absent).error == HeaderError.InvalidOwner
doAssert unsignedPart(absent).error == HeaderError.InvalidOwner
doAssert encodeOwnedHeader(absent, output).error == HeaderError.InvalidOwner
doAssert unsignedHeaderInfo(absentUnsigned).error == HeaderError.InvalidOwner
doAssert headerEpoch(absentUnsigned).error == HeaderError.InvalidOwner
doAssert headerWinners(absentUnsigned).error == HeaderError.InvalidOwner
doAssert headerOffenderAt(absentUnsigned, 0).error == HeaderError.InvalidOwner
doAssert encodeOwnedUnsignedHeader(absentUnsigned, output).error == HeaderError.InvalidOwner
doAssert epochMarkerInfo(absentEpoch).error == HeaderError.InvalidOwner
doAssert epochValidatorAt(absentEpoch, 0).error == HeaderError.InvalidOwner
doAssert encodeOwnedEpochMarker(absentEpoch, output).error == HeaderError.InvalidOwner
doAssert winnersMarkerInfo(absentWinners).error == HeaderError.InvalidOwner
doAssert winningTicketAt(absentWinners, 0).error == HeaderError.InvalidOwner
doAssert encodeOwnedWinnersMarker(absentWinners, output).error == HeaderError.InvalidOwner
# A late author/count/source failure must precede even a zero-capacity output check.
value = sample(); value.unsigned.author = AuthorIndex(6)
for i in 0..<output.len: output[i] = 0xA5
var empty: seq[byte]
doAssert encodeHeader(value, config, output).error == HeaderError.InvalidAuthor
doAssert encodeHeader(value, config, empty).error == HeaderError.InvalidAuthor
for octet in output: doAssert octet == 0xA5 # No parent/marker/proof prefix was emitted before rejection.
value = sample(); value.unsigned.offenders = newSeq[HeaderEdKey](33)
doAssert encodeHeader(value, config, output).error == HeaderError.LimitExceeded
for octet in output: doAssert octet == 0xA5 # Offender ceiling failure is also whole-destination atomic.
# Short immutable output paths leave every destination byte untouched.
doAssert encodeOwnedHeader(decoded.owner, empty).error == HeaderError.OutputTooSmall
doAssert encodeOwnedUnsignedHeader(unsigned, empty).error == HeaderError.OutputTooSmall
doAssert encodeOwnedEpochMarker(retained.epoch, empty).error == HeaderError.OutputTooSmall
doAssert encodeOwnedWinnersMarker(retained.winners, empty).error == HeaderError.OutputTooSmall
# Source allocations have genuine spare backing bytes for full-destination alias tests.
value = sample(); value.unsigned.epoch.validators = newSeq[EpochValidator](128)
value.unsigned.epoch.validators.setLen(6)
let keyBytes = cast[ptr UncheckedArray[byte]](addr value.unsigned.epoch.validators[0])
doAssert encodeHeader(value, config, keyBytes.toOpenArray(0, size-1)).error ==
    HeaderError.AliasedBuffers
# Standalone marker composition must apply the same complete-source overlap policy.
doAssert encodeEpochMarker(value.unsigned.epoch, config, keyBytes.toOpenArray(0,
    epochSize-1)).error == HeaderError.AliasedBuffers
value = sample(); value.unsigned.winners.tickets = newSeq[WinningTicket](128)
value.unsigned.winners.tickets.setLen(12)
let winnerBytes = cast[ptr UncheckedArray[byte]](addr value.unsigned.winners.tickets[0])
doAssert encodeHeader(value, config, winnerBytes.toOpenArray(0, size-1)).error ==
    HeaderError.AliasedBuffers
# The optional winner tag cannot overwrite an earlier/later source ticket during standalone encoding.
doAssert encodeWinnersMarker(value.unsigned.winners, config, winnerBytes.toOpenArray(0,
    winnersSize-1)).error == HeaderError.AliasedBuffers
value = sample(); value.unsigned.offenders = newSeq[HeaderEdKey](128)
value.unsigned.offenders.setLen(3)
let offenderBytes = cast[ptr UncheckedArray[byte]](addr value.unsigned.offenders[0])
doAssert encodeHeader(value, config, offenderBytes.toOpenArray(0, size-1)).error ==
    HeaderError.AliasedBuffers
# Bare source objects contain enough actual fixed storage for their smaller no-marker wire prefixes.
value = Header()
doAssert sizeof(Header) >= 297
let outer = cast[ptr UncheckedArray[byte]](addr value)
doAssert encodeHeader(value, config, outer.toOpenArray(0, 296)).error == HeaderError.AliasedBuffers
var bare: UnsignedHeader
doAssert sizeof(UnsignedHeader) >= 201
let bareBytes = cast[ptr UncheckedArray[byte]](addr bare)
doAssert encodeUnsignedHeader(bare, config, bareBytes.toOpenArray(0, 200)).error ==
    HeaderError.AliasedBuffers
# Fixed record alias checks guard the E1 source byte as well as its 32-byte identity.
var ticket: WinningTicket
let ticketBytes = cast[ptr UncheckedArray[byte]](addr ticket)
doAssert encodeWinningTicket(ticket, ticketBytes.toOpenArray(0, 32)).error ==
    HeaderError.AliasedBuffers
# Present/absent standalone marker descriptors are source storage too, even when only one tag is written.
var epoch = EpochMarker(present: false)
let epochBytes = cast[ptr UncheckedArray[byte]](addr epoch)
doAssert encodeEpochMarker(epoch, config, epochBytes.toOpenArray(0, 0)).error ==
    HeaderError.AliasedBuffers
var winners = WinnersMarker(present: false)
let winnersBytes = cast[ptr UncheckedArray[byte]](addr winners)
doAssert encodeWinnersMarker(winners, config, winnersBytes.toOpenArray(0, 0)).error ==
    HeaderError.AliasedBuffers
# Huge positive epoch lengths cannot overflow a scan or allocate a guessed winner sequence.
var huge = config
huge.epochSlots = EpochSlots(high(uint64))
doAssert decodeWinnersMarker(@[1'u8], huge).error == HeaderError.Truncated
doAssert checked(winnersMarkerInfo(checked(decodeWinnersMarker(@[0'u8], huge)).owner)).present == false
# Optimized builds retain both success-result guards and absent-marker alternative guards.
var guarded = false
try:
  discard decodeHeader(@[255'u8], config).value.consumed
except FieldDefect:
  guarded = true # A failed scan cannot expose default full-header progress.
doAssert guarded
let absentInfo = checked(epochMarkerInfo(checked(decodeEpochMarker(@[0'u8], config)).owner))
var optionalGuarded = false
try:
  discard absentInfo.entropy
except FieldDefect:
  optionalGuarded = true # Validated absence cannot masquerade as a present all-zero entropy.
doAssert optionalGuarded
var defaultResult: HeaderResult[int]
doAssert defaultResult.error == HeaderError.Uninitialized

echo "Nim headers/markers: signing prefix, retained views, guarded results, atomicity and aliases passed"
