## Native full/unsigned/marker ownership, lifetime, atomicity, alias and guarded-alternative regressions.
import ../../support/arc_evidence
import std/[assertions, syncio]
import ../../../src/codec/[header, bounded, assurances, tickets]

# Expected-success paths select the result branch before accessing complete values/progress.
proc checked[T](parsed: HeaderResult[T]): T =
  assert parsed.error == HeaderError.None
  parsed.value

# Fixed public fixture bytes make identity/proof roles visible without a crypto dependency.
proc bytes[N: static[int]](value: byte): array[N, byte] =
  result = default(array[N, byte])
  # Every fixed field owns its exact bytes and no source pointer survives.
  for i in 0..<N: result[i] = value

# A coherent two-marker source keeps validator order, E1 attempts and unsorted duplicate offenders explicit.
proc sample(): Header =
  result = default(Header)
  result.unsigned.parent = HeaderParent(bytes[32](1))
  result.unsigned.priorState = PriorStateRoot(bytes[32](2))
  result.unsigned.extrinsics = ExtrinsicRoot(bytes[32](3))
  result.unsigned.slot = HeaderSlot(0x12345678)
  result.unsigned.author = AuthorIndex(5)
  result.unsigned.entropyProof = HeaderEntropyProof(bytes[96](77))
  result.seal = HeaderSeal(bytes[96](99))
  result.unsigned.epoch = presentEpoch(EpochEntropy(bytes[32](4)), TicketsEntropy(bytes[32](5)),
      newSeq[EpochValidator](6))
  # Reversed key identities preserve their validator-index ordering rather than becoming a set.
  for i in 0..<6:
    editEpochValidators(result.unsigned.epoch)[i].bandersnatch = HeaderBsKey(bytes[32](byte(10-i)))
    editEpochValidators(result.unsigned.epoch)[i].ed25519 = HeaderEdKey(bytes[32](byte(20-i)))
  result.unsigned.winners = presentWinners(newSeq[WinningTicket](12))
  # Full E1 values remain exactly one attempt octet even above compact-natural boundaries.
  for i in 0..<12:
    editWinnerTickets(result.unsigned.winners)[i] = WinningTicket(id: WinningTicketId(bytes[32](
        byte(30-i))), attempt: TicketAttempt(255-i))
  result.unsigned.offenders = @[HeaderEdKey(bytes[32](8)), HeaderEdKey(bytes[32](7)), HeaderEdKey(
      bytes[32](8))]

let config = HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
  epochSlots: EpochSlots(12), maxBytes: ByteLimit(1024*1024))
var value = sample()
var output: array[4096, byte] = default(array[4096, byte])
let size = checked(encodeHeader(value, config, output))
let decoded = checked(decodeHeader(output.toOpenArray(0, size-1), config))
let info = checked(headerInfo(decoded.owner))
assert info.consumed == size and info.unsigned.consumed+96 == size
let unsigned = checked(unsignedPart(decoded.owner))
var signing: array[4096, byte] = default(array[4096, byte])
let signingSize = checked(encodeOwnedUnsignedHeader(unsigned, signing))
assert signingSize == size-96
# Signing payload retains both markers, entropy proof and offender keys, omitting only the final seal.
for i in 0..<signingSize: assert signing[i] == output[i]
for i in 0..<96: assert output[signingSize+i] == 99 # Seal bytes occur last, not before offenders.
assert checked(decodeUnsignedHeader(output.toOpenArray(0, size-1), config)).consumed == signingSize
assert decodeHeader(output.toOpenArray(0, signingSize-1), config).error == HeaderError.Truncated
# Retained fixed metadata and nested owners survive mutation of every original input byte and typed source.
for i in 0..<output.len: output[i] = 0
editWinnerTickets(value.unsigned.winners)[0].attempt = TicketAttempt(0)
assert uint8(checked(winningTicketAt(checked(headerWinners(unsigned)), 0)).attempt) == 255

# Return only retained views after explicitly releasing the full parent and destroying caller bytes.
proc retainViews(config: HeaderConfig): tuple[unsigned: OwnedUnsignedHeader,
    epoch: OwnedEpochMarker, winners: OwnedWinnersMarker] =
  result = default(tuple[unsigned: OwnedUnsignedHeader, epoch: OwnedEpochMarker,
      winners: OwnedWinnersMarker])
  var wire: array[4096, byte] = default(array[4096, byte])
  let count = checked(encodeHeader(sample(), config, wire))
  var parent = checked(decodeHeader(wire.toOpenArray(0, count-1), config)).owner
  result.unsigned = checked(unsignedPart(parent))
  result.epoch = checked(headerEpoch(result.unsigned))
  result.winners = checked(headerWinners(result.unsigned))
  parent = OwnedHeader()
  # ARC child references retain the private parent snapshot after source stack storage disappears.
  for i in 0..<wire.len: wire[i] = 0

var retained = retainViews(config)
assert uint32(checked(unsignedHeaderInfo(retained.unsigned)).slot) == 0x12345678
retained.unsigned = OwnedUnsignedHeader()
assert array[32, byte](checked(epochValidatorAt(retained.epoch, 0)).ed25519) == bytes[32](20)
assert uint8(checked(winningTicketAt(retained.winners, 0)).attempt) == 255
# Child re-emission must use its own exact original marker interval inside the retained full header.
value = sample()
var marker: array[2048, byte] = default(array[2048, byte])
let epochSize = checked(encodeEpochMarker(value.unsigned.epoch, config, marker))
for i in 0..<output.len: output[i] = 0xA5 # Track the complete unused destination suffix too.
assert checked(encodeOwnedEpochMarker(retained.epoch, output)) == epochSize
for i in 0..<epochSize: assert output[i] == marker[i] # Entropies/count/indexed key bytes agree.
for i in epochSize..<output.len: assert output[i] ==
    0xA5 # Owner extraction never writes unrelated capacity.
let winnersSize = checked(encodeWinnersMarker(value.unsigned.winners, config, marker))
assert checked(encodeOwnedWinnersMarker(retained.winners, output)) == winnersSize
for i in 0..<winnersSize: assert output[i] == marker[i] # Fixed tuple has no extra count octet.
# Missing handles cannot manufacture validated absence, unsigned prefixes, child markers or proofs.
var absent: OwnedHeader = default(OwnedHeader)
var absentUnsigned: OwnedUnsignedHeader = default(OwnedUnsignedHeader)
var absentEpoch: OwnedEpochMarker = default(OwnedEpochMarker)
var absentWinners: OwnedWinnersMarker = default(OwnedWinnersMarker)
assert headerInfo(absent).error == HeaderError.InvalidOwner
assert unsignedPart(absent).error == HeaderError.InvalidOwner
assert encodeOwnedHeader(absent, output).error == HeaderError.InvalidOwner
assert unsignedHeaderInfo(absentUnsigned).error == HeaderError.InvalidOwner
assert headerEpoch(absentUnsigned).error == HeaderError.InvalidOwner
assert headerWinners(absentUnsigned).error == HeaderError.InvalidOwner
assert headerOffenderAt(absentUnsigned, 0).error == HeaderError.InvalidOwner
assert encodeOwnedUnsignedHeader(absentUnsigned, output).error == HeaderError.InvalidOwner
assert epochMarkerInfo(absentEpoch).error == HeaderError.InvalidOwner
assert epochValidatorAt(absentEpoch, 0).error == HeaderError.InvalidOwner
assert encodeOwnedEpochMarker(absentEpoch, output).error == HeaderError.InvalidOwner
assert winnersMarkerInfo(absentWinners).error == HeaderError.InvalidOwner
assert winningTicketAt(absentWinners, 0).error == HeaderError.InvalidOwner
assert encodeOwnedWinnersMarker(absentWinners, output).error == HeaderError.InvalidOwner
# A late author/count/source failure must precede even a zero-capacity output check.
value = sample(); value.unsigned.author = AuthorIndex(6)
for i in 0..<output.len: output[i] = 0xA5
var empty: seq[byte] = default(seq[byte])
assert encodeHeader(value, config, output).error == HeaderError.InvalidAuthor
assert encodeHeader(value, config, empty).error == HeaderError.InvalidAuthor
for octet in output: assert octet == 0xA5 # No parent/marker/proof prefix was emitted before rejection.
value = sample(); value.unsigned.offenders = newSeq[HeaderEdKey](33)
assert encodeHeader(value, config, output).error == HeaderError.LimitExceeded
for octet in output: assert octet == 0xA5 # Offender ceiling failure is also whole-destination atomic.
# Short immutable output paths leave every destination byte untouched.
assert encodeOwnedHeader(decoded.owner, empty).error == HeaderError.OutputTooSmall
assert encodeOwnedUnsignedHeader(unsigned, empty).error == HeaderError.OutputTooSmall
assert encodeOwnedEpochMarker(retained.epoch, empty).error == HeaderError.OutputTooSmall
assert encodeOwnedWinnersMarker(retained.winners, empty).error == HeaderError.OutputTooSmall
# Source allocations have genuine spare backing bytes for full-destination alias tests.
value = sample(); value.unsigned.epoch = presentEpoch(value.unsigned.epoch.entropy,
    value.unsigned.epoch.ticketsEntropy, newSeq[EpochValidator](128))
editEpochValidators(value.unsigned.epoch).setLen(6)
let keyBytes = cast[ptr array[128*sizeof(EpochValidator), byte]](addr editEpochValidators(
    value.unsigned.epoch)[0])
assert encodeHeader(value, config, keyBytes[].toOpenArray(0, size-1)).error ==
    HeaderError.AliasedBuffers
# Standalone marker composition must apply the same complete-source overlap policy.
assert encodeEpochMarker(value.unsigned.epoch, config, keyBytes[].toOpenArray(0,
    epochSize-1)).error == HeaderError.AliasedBuffers
value = sample(); value.unsigned.winners = presentWinners(newSeq[WinningTicket](128))
editWinnerTickets(value.unsigned.winners).setLen(12)
let winnerBytes = cast[ptr array[128*sizeof(WinningTicket), byte]](addr editWinnerTickets(
    value.unsigned.winners)[0])
assert encodeHeader(value, config, winnerBytes[].toOpenArray(0, size-1)).error ==
    HeaderError.AliasedBuffers
# The optional winner tag cannot overwrite an earlier/later source ticket during standalone encoding.
assert encodeWinnersMarker(value.unsigned.winners, config, winnerBytes[].toOpenArray(0,
    winnersSize-1)).error == HeaderError.AliasedBuffers
value = sample(); value.unsigned.offenders = newSeq[HeaderEdKey](128)
value.unsigned.offenders.setLen(3)
let offenderBytes = cast[ptr array[128*sizeof(HeaderEdKey), byte]](addr value.unsigned.offenders[0])
assert encodeHeader(value, config, offenderBytes[].toOpenArray(0, size-1)).error ==
    HeaderError.AliasedBuffers
# Bare source objects contain enough actual fixed storage for their smaller no-marker wire prefixes.
value = Header()
assert sizeof(Header) >= 297
let outer = cast[ptr array[sizeof(Header), byte]](addr value)
assert encodeHeader(value, config, outer[].toOpenArray(0, 296)).error == HeaderError.AliasedBuffers
var bare: UnsignedHeader = default(UnsignedHeader)
assert sizeof(UnsignedHeader) >= 201
let bareBytes = cast[ptr array[sizeof(UnsignedHeader), byte]](addr bare)
assert encodeUnsignedHeader(bare, config, bareBytes[].toOpenArray(0, 200)).error ==
    HeaderError.AliasedBuffers
# Fixed record alias checks guard the E1 source byte as well as its 32-byte identity.
var ticket: WinningTicket = default(WinningTicket)
let ticketBytes = cast[ptr array[sizeof(WinningTicket), byte]](addr ticket)
assert encodeWinningTicket(ticket, ticketBytes[].toOpenArray(0, 32)).error ==
    HeaderError.AliasedBuffers
# Present/absent standalone marker descriptors are source storage too, even when only one tag is written.
var epoch = absentEpoch()
let epochBytes = cast[ptr array[sizeof(EpochMarker), byte]](addr epoch)
assert encodeEpochMarker(epoch, config, epochBytes[].toOpenArray(0, 0)).error ==
    HeaderError.AliasedBuffers
var winners = absentWinners()
let winnersBytes = cast[ptr array[sizeof(WinnersMarker), byte]](addr winners)
assert encodeWinnersMarker(winners, config, winnersBytes[].toOpenArray(0, 0)).error ==
    HeaderError.AliasedBuffers
# Huge positive epoch lengths cannot overflow a scan or allocate a guessed winner sequence.
var huge = config
huge.epochSlots = EpochSlots(high(uint64))
assert decodeWinnersMarker(@[1'u8], huge).error == HeaderError.Truncated
assert checked(winnersMarkerInfo(checked(decodeWinnersMarker(@[0'u8], huge)).owner)).present == false
# Failed results and absent alternatives are checked by independent exact-contract subprocesses.
assert decodeHeader(@[255'u8], config).error == HeaderError.Truncated
var defaultResult: HeaderResult[int] = default(HeaderResult[int])
assert defaultResult.error == HeaderError.Uninitialized

# Public read-only source sequence access returns independent values rather than hidden mutable aliases.
var copiedSource = sample()
var copiedKeys = epochValidatorCopies(copiedSource.unsigned.epoch)
var copiedTickets = winnerTicketCopies(copiedSource.unsigned.winners)
copiedKeys[0].ed25519 = HeaderEdKey(bytes[32](0))
copiedTickets[0].attempt = TicketAttempt(0)
assert array[32, byte](editEpochValidators(copiedSource.unsigned.epoch)[0].ed25519) == bytes[32](20)
assert uint8(editWinnerTickets(copiedSource.unsigned.winners)[0].attempt) == 255

# Capture a local complete header; subsequent source edits and stack-buffer erasure cannot affect the owner.
proc capture(marker: byte): OwnedHeader =
  var source = sample()
  source.unsigned.slot = HeaderSlot(uint32(marker))
  source.seal = HeaderSeal(bytes[96](marker))
  source.unsigned.epoch = presentEpoch(EpochEntropy(bytes[32](marker)),
      source.unsigned.epoch.ticketsEntropy,
    epochValidatorCopies(source.unsigned.epoch))
  editWinnerTickets(source.unsigned.winners)[0].attempt = TicketAttempt(marker)
  var wire = default(array[4096, byte])
  let count = checked(encodeHeader(source, config, wire))
  let captured = checked(decodeHeader(wire.toOpenArray(0, count-1), config)).owner
  editWinnerTickets(source.unsigned.winners)[0].attempt = TicketAttempt(marker xor 255)
  for octet in wire.mitems: octet = 0
  captured

# Replacing the original full handle must leave old aliases and selected nested views intact.
proc escaped(marker: byte): tuple[unsigned: OwnedUnsignedHeader, epoch: OwnedEpochMarker,
    winners: OwnedWinnersMarker] =
  var parent = capture(marker)
  let retained = parent
  parent = capture(marker xor 255)
  assert uint32(checked(headerInfo(parent)).unsigned.slot) == uint32(marker xor 255)
  assert array[96, byte](checked(headerInfo(retained)).seal)[95] == marker
  let unsigned = checked(unsignedPart(retained))
  (unsigned, checked(headerEpoch(unsigned)), checked(headerWinners(unsigned)))

# Every isolated scope releases full parents, signing views and marker views at their last ARC reference.
proc releaseCycle(marker: byte) =
  var views = escaped(marker)
  assert uint32(checked(unsignedHeaderInfo(views.unsigned)).slot) == uint32(marker)
  var signing = default(array[4096, byte])
  let count = checked(encodeOwnedUnsignedHeader(views.unsigned, signing))
  assert checked(decodeUnsignedHeader(signing.toOpenArray(0, count-1), config)).consumed == count
  views.unsigned = default(OwnedUnsignedHeader)
  assert array[32, byte](checked(epochMarkerInfo(views.epoch)).entropy)[0] == marker
  assert uint8(checked(winningTicketAt(views.winners, 0)).attempt) == marker
  assert array[32, byte](checked(epochValidatorAt(views.epoch, 0)).ed25519) == bytes[32](20)
  var wire = default(array[2048, byte])
  assert checked(encodeOwnedEpochMarker(views.epoch, wire)) > 1
  assert checked(encodeOwnedWinnersMarker(views.winners, wire)) == 1+12*33

# Warm up the public live-memory counter before observing independently released ARC scopes.
for i in 0..<100: releaseCycle(byte(i mod 256))
let beforeRelease = getOccupiedMem()
# Vary fixed data while all temporary sources, buffers, parents and child views expire on each return.
for i in 0..<1000: releaseCycle(byte(i mod 256))
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Retain numeric observations without platform-specific heap sizes in expected output.
recordArcRelease("header", 1000, beforeRelease, afterRelease)
echo "HEADER_ARC_RELEASE cycles=1000 unchanged"
echo "Headers/markers: signing prefixes, retained replacements, guarded alternatives, aliases and ARC release passed"
