## Focused public composite ownership, child materialization, stricter-policy and atomicity regressions.
import std/os
import ../../src/codec/[block_codec, bounded, composite, owned, tickets, assurances, guarantees,
    disputes, header]

# Select complete successful parent values before reading fields/progress.
proc checked[T](parsed: FrameResult[T]): T =
  doAssert parsed.error == FrameError.None
  parsed.value

# Read only public test fixtures into mutable request-owned octets, with no type-punned string storage.
proc bytes(path: string): seq[byte] =
  let text = readFile(path)
  result = newSeq[byte](text.len)
  for i in 0..<text.len: result[i] = byte(text[i]) # Every source byte can safely be overwritten after capture.

let config = FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6), epochSlots: EpochSlots(12),
  ticketLimit: TicketLimit(3), preimages: PreimageLimits(items: ElementLimit(10000),
    perBlob: ByteLimit(16777216), totalBlobBytes: ByteLimit(16777216)), maxBytes: ByteLimit(16777216))

# Capture separately authored complete child fixtures; no parent decoder constructs the source for encoding tests.
proc source(config: FrameConfig): Extrinsic =
  let folder = paramStr(1)
  result.tickets = checked(decodeComponent[ComponentKind.Tickets](bytes(folder/"tickets.bin"), config)).owner
  result.preimages = checked(decodeComponent[ComponentKind.Preimages](bytes(folder/"preimages.bin"), config)).owner
  result.guarantees = checked(decodeComponent[ComponentKind.Guarantees](bytes(
      folder/"guarantees.bin"), config)).owner
  result.assurances = checked(decodeComponent[ComponentKind.Assurances](bytes(
      folder/"assurances.bin"), config)).owner
  result.disputes = checked(decodeComponent[ComponentKind.Disputes](bytes(folder/"disputes.bin"), config)).owner

var value = source(config)
let parent = checked(ownExtrinsic(value, config))
value = Extrinsic()
var output: array[20000, byte]
let size = checked(encodeOwnedExtrinsic(parent, output))
let parsed = checked(decodeExtrinsic(output.toOpenArray(0, size-1), config))
# Parent capture keeps exact immutable children after all original input contents and source descriptors disappear.
for i in 0..<output.len: output[i] = 0
var ticketPart = checked(extrinsicTickets(parsed.owner))
var copies = checked(readTickets(ticketPart))
doAssert copies.len == 3
let originalAttempt = copies[0].attempt
copies[0].attempt = TicketAttempt(255)
doAssert checked(readTickets(ticketPart))[0].attempt == originalAttempt
let assurancePart = checked(extrinsicAssurances(parsed.owner))
var assuranceCopies = checked(readAssurances(assurancePart))
doAssert assuranceCopies.len == 2
let bits = assuranceCopies[0].bits
assuranceCopies[0].bits.bytes[0] = 0
doAssert checked(readAssurances(assurancePart))[0].bits.bytes == bits.bytes
# Existing payload/report/disputes APIs are materialized as independent immutable owners on demand.
let p = readPreimages(checked(extrinsicPreimages(parsed.owner)))
doAssert p.error == OwnershipError.None
let preimageInfo = ownedInfo(p.value)
doAssert preimageInfo.error == OwnershipError.None
doAssert preimageInfo.value.kind == OwnedKind.Preimages
let g = readGuarantees(checked(extrinsicGuarantees(parsed.owner)))
doAssert g.error == GuaranteeError.None and g.value.count == 1
let d = readDisputes(checked(extrinsicDisputes(parsed.owner)))
doAssert d.error == DisputeError.None and d.value.info.verdicts == 2
# A complete block is sourced from the existing owned extrinsic and an independently captured sealed header.
let h = checked(decodeComponent[ComponentKind.Header](bytes(paramStr(1)/"header.bin"), config)).owner
let blockSource = Block(header: h, extrinsic: parent)
let blockSize = checked(encodeBlock(blockSource, config, output))
var blockOwner = checked(decodeBlock(output.toOpenArray(0, blockSize-1), config)).owner
let retainedHeader = checked(blockHeader(blockOwner))
let retainedExtrinsic = checked(blockExtrinsic(blockOwner))
ticketPart = checked(extrinsicTickets(retainedExtrinsic))
blockOwner = OwnedBlock()
for i in 0..<output.len: output[i] = 0 # Caller source lifetime/content no longer identifies any retained child.
doAssert checked(readTickets(ticketPart)).len == 3
doAssert readHeader(retainedHeader).error == HeaderError.None
# Later stricter policies must be reapplied to immutable sources rather than trusting earlier broader capture limits.
var strict = config
strict.ticketLimit = TicketLimit(0)
for i in 0..<output.len: output[i] = 0xA5
let refused = encodeBlock(blockSource, strict, output)
doAssert refused.error == FrameError.InvalidComponent
doAssert refused.cause.kind == ComponentKind.Tickets and refused.cause.ticketError ==
    TicketError.LimitExceeded
for octet in output: doAssert octet == 0xA5 # Even a valid complete header cannot write before the final parent policy passes.
var empty: seq[byte]
doAssert encodeBlock(blockSource, strict, empty).error == FrameError.InvalidComponent
strict = config; strict.preimages.totalBlobBytes = ByteLimit(0)
let refusedLate = encodeBlock(blockSource, strict, output)
doAssert refusedLate.error == FrameError.InvalidComponent and refusedLate.cause.kind ==
    ComponentKind.Preimages
for octet in output: doAssert octet == 0xA5 # New payload policy cannot bypass whole-block atomicity.
# Too-small destinations preserve all bytes for parent and component owner re-emission.
doAssert encodeOwnedExtrinsic(parent, empty).error == FrameError.OutputTooSmall
doAssert encodeComponent(ticketPart, empty).error == FrameError.OutputTooSmall
doAssert encodeBlock(blockSource, config, empty).error == FrameError.OutputTooSmall
# Fresh captures own bytes, so reusing their original caller buffer as output is safe and deliberately supported.
var original = bytes(paramStr(1)/"tickets.bin")
let independent = checked(decodeComponent[ComponentKind.Tickets](original, config)).owner
for i in 0..<original.len: original[i] = 0
doAssert checked(encodeComponent(independent, original)) == original.len
# Default parents/components return ordinary failure rather than fabricated complete empty frames or copied records.
var absentExtrinsic: OwnedExtrinsic
var absentBlock: OwnedBlock
var absentTickets: TicketComponent
var absentSource: Extrinsic
doAssert extrinsicInfo(absentExtrinsic).error == FrameError.InvalidOwner
doAssert extrinsicTickets(absentExtrinsic).error == FrameError.InvalidOwner
doAssert encodeOwnedExtrinsic(absentExtrinsic, output).error == FrameError.InvalidOwner
doAssert blockInfo(absentBlock).error == FrameError.InvalidOwner
doAssert blockHeader(absentBlock).error == FrameError.InvalidOwner
doAssert blockExtrinsic(absentBlock).error == FrameError.InvalidOwner
doAssert encodeOwnedBlock(absentBlock, output).error == FrameError.InvalidOwner
doAssert componentInfo(absentTickets).error == FrameError.InvalidOwner
doAssert readTickets(absentTickets).error == FrameError.InvalidOwner
doAssert encodeExtrinsic(absentSource, config, output).error == FrameError.InvalidOwner
doAssert ownExtrinsic(absentSource, config).error == FrameError.InvalidOwner
# A validated empty extrinsic is seven count bytes, retaining five nondefault schema-specific children.
var zero: Extrinsic
zero.tickets = checked(decodeComponent[ComponentKind.Tickets](@[0'u8], config)).owner
zero.preimages = checked(decodeComponent[ComponentKind.Preimages](@[0'u8], config)).owner
zero.guarantees = checked(decodeComponent[ComponentKind.Guarantees](@[0'u8], config)).owner
zero.assurances = checked(decodeComponent[ComponentKind.Assurances](@[0'u8], config)).owner
zero.disputes = checked(decodeComponent[ComponentKind.Disputes](@[0'u8, 0, 0], config)).owner
let zeroOwner = checked(ownExtrinsic(zero, config))
doAssert checked(extrinsicInfo(zeroOwner)).consumed == 7
let alias = cast[ptr UncheckedArray[byte]](addr zero)
doAssert encodeExtrinsic(zero, config, alias.toOpenArray(0, 6)).error == FrameError.AliasedBuffers
# A real array provides enough backing bytes for a whole-block descriptor alias fixture without out-of-bounds buffers.
var backing: array[2048, Block]
backing[0] = blockSource
let descriptorBytes = cast[ptr UncheckedArray[byte]](addr backing[0])
doAssert sizeof(backing) >= blockSize
doAssert encodeBlock(backing[0], config, descriptorBytes.toOpenArray(0, blockSize-1)).error ==
    FrameError.AliasedBuffers
# A different epoch parameter must not reinterpret an already captured header as a shorter standalone prefix.
var winnerHeader = header.Header()
winnerHeader.unsigned.winners = WinnersMarker(present: true, tickets: newSeq[WinningTicket](12))
var headerBuffer: array[2048, byte]
let headerCount = encodeHeader(winnerHeader, header.HeaderConfig(cores: config.cores,
  authorValidators: config.validators, epochSlots: config.epochSlots, maxBytes: config.maxBytes), headerBuffer)
doAssert headerCount.error == HeaderError.None
let headerComponent = checked(decodeComponent[ComponentKind.Header](headerBuffer.toOpenArray(0,
    headerCount.value-1), config)).owner
var changed = config
changed.epochSlots = EpochSlots(1)
let reinterpreted = encodeBlock(Block(header: headerComponent, extrinsic: zeroOwner), changed, output)
doAssert reinterpreted.error == FrameError.InvalidConfig
# Runtime guards preserve failed-result and wrong-component-cause alternatives in checked optimized builds.
var guarded = false
try:
  # Deliberately reading a rejected branch must trigger the enabled variant guard.
  discard decodeBlock(@[255'u8], config).value.consumed
except FieldDefect:
  guarded = true # No default block/progress may be read from a rejected header.
doAssert guarded
var causeGuarded = false
try:
  # A selected ticket reason must reject access to the header-only alternative.
  discard refused.cause.headerError
except FieldDefect:
  causeGuarded = true # Ticket failures cannot masquerade as a header error or publish mismatched cause fields.
doAssert causeGuarded

echo "Nim blocks/extrinsics: retained children, typed causes, independent copies, policy and atomicity passed"
