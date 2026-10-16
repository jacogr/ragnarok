## Focused public composite ownership, child materialization, stricter-policy and atomicity regressions.
import std/[assertions, cmdline, syncio]
import ../../src/codec/[block_codec, bounded, composite, owned, tickets, assurances, guarantees,
    disputes, header]

# Select complete successful parent values before reading fields/progress.
proc checked[T](parsed: FrameResult[T]): T =
  assert parsed.error == FrameError.None
  parsed.value

# Read only public test fixtures into mutable request-owned octets, with no type-punned string storage.
proc bytes(path: string): seq[byte] {.raises.} =
  let text = readFile(path)
  result = newSeq[byte](text.len)
  for i in 0..<text.len: result[i] = byte(text[i]) # Every source byte can safely be overwritten after capture.

let config = FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6), epochSlots: EpochSlots(12),
  ticketLimit: TicketLimit(3), preimages: PreimageLimits(items: ElementLimit(10000),
    perBlob: ByteLimit(16777216), totalBlobBytes: ByteLimit(16777216)), maxBytes: ByteLimit(16777216))

# Capture separately authored complete child fixtures; no parent decoder constructs the source for encoding tests.
proc source(config: FrameConfig): Extrinsic {.raises.} =
  result = default(Extrinsic)
  let folder = paramStr(1)
  result.tickets = checked(decodeComponent[ComponentKind.Tickets](bytes(folder & "/tickets.bin"), config)).owner
  result.preimages = checked(decodeComponent[ComponentKind.Preimages](bytes(folder &
      "/preimages.bin"), config)).owner
  result.guarantees = checked(decodeComponent[ComponentKind.Guarantees](bytes(
      folder & "/guarantees.bin"), config)).owner
  result.assurances = checked(decodeComponent[ComponentKind.Assurances](bytes(
      folder & "/assurances.bin"), config)).owner
  result.disputes = checked(decodeComponent[ComponentKind.Disputes](bytes(folder & "/disputes.bin"), config)).owner

# Isolate capture/replacement and every child materialization so the final ARC reference dies on return.
proc releaseCycle(source: Block, config: FrameConfig, size: int) =
  var wire = newSeq[byte](size)
  assert checked(encodeBlock(source, config, wire)) == size
  var parent = checked(decodeBlock(wire, config)).owner
  let oldHeader = checked(blockHeader(parent))
  var child = checked(blockExtrinsic(parent))
  let oldSlot = headerInfo(readHeader(oldHeader).value.owner).value.unsigned.slot
  # Slot begins after three fixed 32-byte commitments; changing its low byte keeps this source structurally valid.
  wire[96] = wire[96] xor 1
  parent = checked(decodeBlock(wire, config)).owner
  assert uint32(headerInfo(readHeader(checked(blockHeader(
      parent))).value.owner).value.unsigned.slot) != uint32(oldSlot)
  let tickets = checked(extrinsicTickets(child))
  let preimages = checked(extrinsicPreimages(child))
  let guarantees = checked(extrinsicGuarantees(child))
  let assurances = checked(extrinsicAssurances(child))
  let disputes = checked(extrinsicDisputes(child))
  parent = default(OwnedBlock)
  child = default(OwnedExtrinsic)
  # Destroy all caller bytes and both parent handles before materializing the retained original children.
  for i in 0..<wire.len: wire[i] = 0
  assert headerInfo(readHeader(oldHeader).value.owner).value.unsigned.slot.uint32 == uint32(oldSlot)
  assert checked(readTickets(tickets)).len == 3
  assert checked(readAssurances(assurances)).len == 2
  assert ownedInfo(readPreimages(preimages).value).value.blobCount == 3
  assert readGuarantees(guarantees).value.count == 1
  assert readDisputes(disputes).value.info.verdicts == 2

# Fixture I/O failures are reported separately from codec failures.
try:
  var value = source(config)
  let parent = checked(ownExtrinsic(value, config))
  value = Extrinsic()
  var output: array[20000, byte] = default(array[20000, byte])
  let size = checked(encodeOwnedExtrinsic(parent, output))
  let parsed = checked(decodeExtrinsic(output.toOpenArray(0, size-1), config))
  # Parent capture keeps exact immutable children after all original input contents and source descriptors disappear.
  for i in 0..<output.len: output[i] = 0
  var ticketPart = checked(extrinsicTickets(parsed.owner))
  var copies = checked(readTickets(ticketPart))
  assert copies.len == 3
  let originalAttempt = copies[0].attempt
  copies[0].attempt = TicketAttempt(255)
  assert checked(readTickets(ticketPart))[0].attempt == originalAttempt
  let assurancePart = checked(extrinsicAssurances(parsed.owner))
  var assuranceCopies = checked(readAssurances(assurancePart))
  assert assuranceCopies.len == 2
  let bits = assuranceCopies[0].bits
  assuranceCopies[0].bits.bytes[0] = 0
  assert checked(readAssurances(assurancePart))[0].bits.bytes == bits.bytes
  # Existing payload/report/disputes APIs are materialized as independent immutable owners on demand.
  let p = readPreimages(checked(extrinsicPreimages(parsed.owner)))
  assert p.error == OwnershipError.None
  let preimageInfo = ownedInfo(p.value)
  assert preimageInfo.error == OwnershipError.None
  assert preimageInfo.value.kind == OwnedKind.Preimages
  let g = readGuarantees(checked(extrinsicGuarantees(parsed.owner)))
  assert g.error == GuaranteeError.None and g.value.count == 1
  let d = readDisputes(checked(extrinsicDisputes(parsed.owner)))
  assert d.error == DisputeError.None and d.value.info.verdicts == 2
  # A complete block is sourced from the existing owned extrinsic and an independently captured sealed header.
  let h = checked(decodeComponent[ComponentKind.Header](bytes(paramStr(1) & "/header.bin"), config)).owner
  let blockSource = Block(header: h, extrinsic: parent)
  let blockSize = checked(encodeBlock(blockSource, config, output))
  var blockOwner = checked(decodeBlock(output.toOpenArray(0, blockSize-1), config)).owner
  let retainedHeader = checked(blockHeader(blockOwner))
  let retainedExtrinsic = checked(blockExtrinsic(blockOwner))
  ticketPart = checked(extrinsicTickets(retainedExtrinsic))
  blockOwner = OwnedBlock()
  for i in 0..<output.len: output[i] = 0 # Caller source lifetime/content no longer identifies any retained child.
  assert checked(readTickets(ticketPart)).len == 3
  assert readHeader(retainedHeader).error == HeaderError.None
  # Later stricter policies must be reapplied to immutable sources rather than trusting earlier broader capture limits.
  var strict = config
  strict.ticketLimit = TicketLimit(0)
  for i in 0..<output.len: output[i] = 0xA5
  let refused = encodeBlock(blockSource, strict, output)
  assert refused.error == FrameError.InvalidComponent
  assert refused.cause.kind == ComponentKind.Tickets and refused.cause.ticketError ==
      TicketError.LimitExceeded
  for octet in output: assert octet == 0xA5 # Even a valid complete header cannot write before the final parent policy passes.
  var empty: seq[byte] = default(seq[byte])
  assert encodeBlock(blockSource, strict, empty).error == FrameError.InvalidComponent
  strict = config; strict.preimages.totalBlobBytes = ByteLimit(0)
  let refusedLate = encodeBlock(blockSource, strict, output)
  assert refusedLate.error == FrameError.InvalidComponent and refusedLate.cause.kind ==
      ComponentKind.Preimages
  for octet in output: assert octet == 0xA5 # New payload policy cannot bypass whole-block atomicity.
  # Too-small destinations preserve all bytes for parent and component owner re-emission.
  assert encodeOwnedExtrinsic(parent, empty).error == FrameError.OutputTooSmall
  assert encodeComponent(ticketPart, empty).error == FrameError.OutputTooSmall
  assert encodeBlock(blockSource, config, empty).error == FrameError.OutputTooSmall
  # Fresh captures own bytes, so reusing their original caller buffer as output is safe and deliberately supported.
  var original = bytes(paramStr(1) & "/tickets.bin")
  let independent = checked(decodeComponent[ComponentKind.Tickets](original, config)).owner
  for i in 0..<original.len: original[i] = 0
  assert checked(encodeComponent(independent, original)) == original.len
  # Default parents/components return ordinary failure rather than fabricated complete empty frames or copied records.
  var absentExtrinsic: OwnedExtrinsic = default(OwnedExtrinsic)
  var absentBlock: OwnedBlock = default(OwnedBlock)
  var absentTickets: TicketComponent = default(TicketComponent)
  var absentSource: Extrinsic = default(Extrinsic)
  assert extrinsicInfo(absentExtrinsic).error == FrameError.InvalidOwner
  assert extrinsicTickets(absentExtrinsic).error == FrameError.InvalidOwner
  assert encodeOwnedExtrinsic(absentExtrinsic, output).error == FrameError.InvalidOwner
  assert blockInfo(absentBlock).error == FrameError.InvalidOwner
  assert blockHeader(absentBlock).error == FrameError.InvalidOwner
  assert blockExtrinsic(absentBlock).error == FrameError.InvalidOwner
  assert encodeOwnedBlock(absentBlock, output).error == FrameError.InvalidOwner
  assert componentInfo(absentTickets).error == FrameError.InvalidOwner
  assert readTickets(absentTickets).error == FrameError.InvalidOwner
  assert encodeExtrinsic(absentSource, config, output).error == FrameError.InvalidOwner
  assert ownExtrinsic(absentSource, config).error == FrameError.InvalidOwner
  # A validated empty extrinsic is seven count bytes, retaining five nondefault schema-specific children.
  var zero: Extrinsic = default(Extrinsic)
  zero.tickets = checked(decodeComponent[ComponentKind.Tickets](@[0'u8], config)).owner
  zero.preimages = checked(decodeComponent[ComponentKind.Preimages](@[0'u8], config)).owner
  zero.guarantees = checked(decodeComponent[ComponentKind.Guarantees](@[0'u8], config)).owner
  zero.assurances = checked(decodeComponent[ComponentKind.Assurances](@[0'u8], config)).owner
  zero.disputes = checked(decodeComponent[ComponentKind.Disputes](@[0'u8, 0, 0], config)).owner
  let zeroOwner = checked(ownExtrinsic(zero, config))
  assert checked(extrinsicInfo(zeroOwner)).consumed == 7
  let alias = cast[ptr array[sizeof(Extrinsic), byte]](addr zero)
  assert encodeExtrinsic(zero, config, alias[].toOpenArray(0, 6)).error == FrameError.AliasedBuffers
  # A real array provides enough backing bytes for a whole-block descriptor alias fixture without out-of-bounds buffers.
  var backing: array[2048, Block] = default(array[2048, Block])
  backing[0] = blockSource
  let descriptorBytes = cast[ptr array[sizeof(backing), byte]](addr backing[0])
  assert sizeof(backing) >= blockSize
  assert encodeBlock(backing[0], config, descriptorBytes[].toOpenArray(0, blockSize-1)).error ==
      FrameError.AliasedBuffers
  # A different epoch parameter must not reinterpret an already captured header as a shorter standalone prefix.
  var winnerHeader = header.Header()
  winnerHeader.unsigned.winners = presentWinners(newSeq[WinningTicket](12))
  var headerBuffer: array[2048, byte] = default(array[2048, byte])
  let headerCount = encodeHeader(winnerHeader, header.HeaderConfig(cores: config.cores,
    authorValidators: config.validators, epochSlots: config.epochSlots, maxBytes: config.maxBytes), headerBuffer)
  assert headerCount.error == HeaderError.None
  let headerComponent = checked(decodeComponent[ComponentKind.Header](headerBuffer.toOpenArray(0,
      headerCount.value-1), config)).owner
  var changed = config
  changed.epochSlots = EpochSlots(1)
  let reinterpreted = encodeBlock(Block(header: headerComponent, extrinsic: zeroOwner), changed, output)
  assert reinterpreted.error == FrameError.InvalidConfig

  # Warm allocator paths before measuring public live occupancy with outer fixtures still retained.
  for i in 0..<100: releaseCycle(blockSource, config, blockSize)
  let beforeRelease = getOccupiedMem()
  # Each completed scope must release every replaced parent, child and independently materialized snapshot.
  for i in 0..<1000: releaseCycle(blockSource, config, blockSize)
  let afterRelease = getOccupiedMem()
  assert beforeRelease == afterRelease
  echo "BLOCK_ARC_RELEASE cycles=1000 occupied_before=", beforeRelease, " occupied_after=", afterRelease
  echo "Nimony blocks/extrinsics: retained children, typed causes, independent copies, policy and atomicity passed"
except:
  # Missing trusted fixtures fail the suite without changing protocol error semantics.
  quit(2)
