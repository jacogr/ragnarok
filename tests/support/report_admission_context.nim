# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared genuinely signed block fixtures for report planning, atomic publication and queue binding.
##
## Exposes authored Context inputs, config/frame/safrole/transitionConfig policies and stage helpers.
## Optional genuine assurance votes make one old report available; these are test fixtures, not APIs
## for constructing production admission certificates. Extra test chapters are committed before signing.

import std/[assertions, envvars, strutils, syncio, sequtils]
import ../../src/state/[report_admission, report_assignments, report_policy, report_anchors,
  report_packages, guarantee_credentials, block_transition, block_admission, store,
  safrole_transition, disputes, availability, report_transition]
import ../../src/codec/[block_codec, header, bounded, guarantees, assurances, state_safrole,
  state_consensus, state_disputes, state_layout, state_trie, state_history, state_availability,
  state_workqueues, state_authorization, state_outputs, tickets, report_owned, owned, work_report,
  composite, work_digest]
import ../../src/crypto/[primitives, extrinsic_commitment, assurance_context]
import ../../src/bandersnatch/bandersnatch
import ./[report_context, service_namespace_seed]
from ../../src/codec/disputes import Disputes, Culprit, DisputeSignature, DisputeConfig,
    encodeDisputes, DisputeError

proc config*(): ReportAdmissionConfig =
  ## Keep all stage domains equal while independently bounding each chapter and ancestor chain.
  let cfg = credentialConfig(2)
  let availability = AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2),
    validators: ValidatorCount(6), maxBytes: ByteLimit(100000)), maxPresent: ElementLimit(2),
    maxBytes: ByteLimit(200000))
  ReportAdmissionConfig(credentials: cfg, policy: policy(2),
    anchors: ReportAnchorConfig(history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8),
      perBlock: ElementLimit(2), totalPackages: ElementLimit(16), peaks: ElementLimit(64),
      maxBytes: ByteLimit(100000)), lookupAge: LookupAge(14400)),
    ancestors: AncestorConfig(header: HeaderConfig(cores: CoreCount(2),
        authorValidators: ValidatorCount(6),
      epochSlots: EpochSlots(12), maxBytes: ByteLimit(100000)), headers: ElementLimit(16),
          maxBytes: ByteLimit(1000000)),
    packages: ReportPackageConfig(availability: availability,
      queues: WorkQueueConfig(epochSlots: EpochSlots(12), cores: CoreCount(2),
          perSlot: ElementLimit(8),
        totalItems: ElementLimit(32), perDependencies: ElementLimit(8),
            totalDependencies: ElementLimit(256),
        reportBytes: ByteLimit(100000), maxBytes: ByteLimit(1000000)), indexItems: ElementLimit(
            1024)),
    judgments: DisputeStateConfig(perSet: ElementLimit(10000), totalItems: ElementLimit(40000),
        maxBytes: ByteLimit(2000000)))

proc frame*(): BlockAdmissionConfig =
  ## The same finite profile applies to both block commitments and stage execution.
  BlockAdmissionConfig(frame: FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      epochSlots: EpochSlots(12),
    ticketLimit: TicketLimit(3), maxBytes: ByteLimit(2000000), preimages: PreimageLimits(
        items: ElementLimit(100),
      perBlob: ByteLimit(100000), totalBlobBytes: ByteLimit(100000))),
          maxParentHeaderBytes: ByteLimit(100000))

proc safrole*(): SafroleTransitionConfig =
  ## Full coordinator policy keeps non-epoch authored fixtures free of unnecessary ring setup.
  SafroleTransitionConfig(state: SafroleStateConfig(validators: credentialConfig(
      2).assignments.roster,
    epochSlots: EpochSlots(12), maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(2000000)),
    tailStart: EpochSlots(10), blockTickets: TicketLimit(3), offenders: ElementLimit(10000),
    maxHeaderBytes: ByteLimit(2000000), maxMarkerBytes: ByteLimit(2000000))

proc transitionConfig*(): BlockReportConfig =
  ## Collect the same finite policies for the atomic publication entry point.
  let cfg = config()
  BlockReportConfig(admission: frame(), safrole: safrole(), reports: cfg,
    disputes: DisputesConfig(rosters: cfg.credentials.assignments.roster, epochSlots: EpochSlots(12),
      state: cfg.judgments, availability: cfg.packages.availability, maxExtrinsicBytes: ByteLimit(
          2000000)),
    availability: AvailabilityTransitionConfig(rosters: cfg.credentials.assignments.roster,
      assignments: cfg.packages.availability, availableReports: ElementLimit(2)))

proc stage*(state: var StateStore, candidate: OwnedBlock,
    parent: OwnedHeader): BlockTransitionResult =
  ## Execute only real coordinator entry points; no forged successful stage value enters report admission.
  let cfg = transitionConfig()
  advanceBlockState(state, candidate, parent, cfg.admission, cfg.disputes, cfg.safrole,
      cfg.availability)

## Serialize a full sealed header independently of its original mutable descriptor.
proc wire(value: header.Header): seq[byte] =
  result = newSeq[byte](100000)
  let written = encodeHeader(value, config().ancestors.header, result)
  assert written.error == HeaderError.None
  result.setLen(written.value)

## Retain one exact authored complete header, including its opaque historical seal.
proc owner(value: header.Header): OwnedHeader =
  decodeHeader(wire(value), config().ancestors.header).value.owner

## Literal domain octets precede a copied fixed VRF input; no implicit terminator or size prefix.
proc transcript(domain: string, seed: array[32, byte]): seq[byte] =
  result = newSeq[byte](domain.len+32)
  for i in 0..<domain.len: result[i] = byte(domain[i]) # Exact token spelling.
  for i in 0..<32: result[domain.len+i] = seed[i] # Fixed raw input.

## Copy a template into an authored report whose recent/lookup tuples refer to the same actual parent chain.
proc report(base: OwnedReport, core: int, root: state_trie.StateRoot, parentHash, lookupHash: array[
    32, byte], mode: int, refinementGas = high(uint64), refinement: seq[RefineLoad] = @[],
    accumulationGas = 10'u64): OwnedReport =
  let raw = reportBytes(reportFor(base, core, [accumulationGas]))
  var value = decodeReportBorrowed(raw, 2).value
  value.header.packageHash.bytes = default(array[32, byte])
  value.header.packageHash.bytes[0] = byte(core+10)
  value.header.anchor.bytes = parentHash
  value.header.stateRoot.bytes = array[32, byte](root)
  value.header.accumulationRoot.bytes = default(array[32, byte])
  value.header.anchorSlot = AnchorSlot(1)
  value.header.lookupAnchor.bytes = lookupHash
  value.header.lookupSlot = LookupSlot(0)
  value.header.lookupStateRoot.bytes = default(array[32, byte])
  value.digests[0].refine.gasUsed = Gas(refinementGas) # Optional bounded activity keeps multi-report aggregation inside its natural domain.
  if refinement.len > core:
    value.digests[0].refine = refinement[core] # Explicit per-core loads override the default before signing.
  value.prerequisiteCount = 0
  value.lookupCount = 0
  if mode == 3: value.header.stateRoot.bytes[0] = value.header.stateRoot.bytes[
      0] xor 1 # Corrected recent tuple must match all fields.
  if mode == 4: value.header.lookupStateRoot.bytes[0] = 1 # Historical child commits a different root.
  var output = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(value, raw, 2, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 2).value

## Override only the authored service code identity before recomputing reports, parent roots and signatures.
proc withCode(base: OwnedReport, code: seq[byte]): OwnedReport =
  let raw = reportBytes(base)
  var value = decodeReportBorrowed(raw, 2).value
  value.digests[0].codeHash = CodeHash(array[32, byte](blake2b256(code).value))
  var output = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(value, raw, 2, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 2).value

## Scoped fixture retains a genuine coordinator result and original signed inputs for independent publication.
type Context* = object
  staged*: BlockTransitionResult
  older*: seq[OwnedHeader]
  original*: StateStore
  candidate*: OwnedBlock
  parent*: OwnedHeader
  source*: seq[StateEntry]

type SignedBlockFixtureConfig* = object ## Authored signed-parent/block data is separate from execution configuration.
  mode*: int                       ## Intentional report/parent damage selector; zero authors a valid block.
  reports*: int                    ## Number of newly guaranteed reports.
  maxWriteBytes*: uint64           ## Inherited store write-byte ceiling.
  withDispute*: bool               ## Include genuine new-offender evidence.
  withAvailable*: bool             ## Assure a previously assigned report.
  extra*: seq[StateEntry]          ## Additional original-parent entries, committed before signing.
  accountTransferGas*: uint64      ## Explicit original recipient threshold; default preserves historical fixtures.
  accountCode*: seq[byte]          ## Optional code preimage bound to signed reports and the account.
  ready*: ReadyRow                 ## Original parent ready row.
  preimageWire*: seq[byte]         ## Exact child preimage extrinsic, including intentional malformed cases.
  poolCopies*: int                 ## Number of original authorizer duplicates per core.
  namespaceValueBytes*: uint64     ## Explicit original namespace fixture bound; existing profiles retain65 bytes.
  accumulationGas*: uint64         ## Declared original report budget, authored before queue roots and signatures.
  refinementGas*: uint64           ## Gas observation encoded in each signed report digest.
  historyPeaks*: seq[HistoryPeak]  ## Original parent history belt.
  targetSlot*: uint32              ## Explicit child slot; zero chooses the existing scenario default.
  withTicket*: bool                ## Include a real RingVRF ticket.
  shiftPending*: bool              ## Rotate pending identities while preserving parent active identities.
  guaranteeSlot*: uint32           ## Explicit signed guarantee slot; zero selects child time.
  refinement*: seq[RefineLoad]     ## Optional per-digest refinement observations.
  parentPools*: seq[AuthorizerRow] ## Explicit canonical original authorizer pools.
  storeWrites*: uint64             ## Inherited store mutation-count ceiling.
  serviceNamespaces*: seq[ServiceNamespaceSeed] ## Opt-in complete original namespaces, authored before all signatures.
  completeState*: bool ## New authored complete-map mode uses empty C16 instead of the rollback-only C250 sentinel.

proc signedBlockFixtureConfig*(): SignedBlockFixtureConfig =
  ## Preserve the existing tiny signed profile and resource defaults in one place.
  SignedBlockFixtureConfig(mode: 0, reports: 2, maxWriteBytes: 1000000'u64, withDispute: false,
      withAvailable: false, extra: @[], accountTransferGas: high(uint64), accountCode: @[],
          ready: @[], preimageWire: @[],
      poolCopies: 1, namespaceValueBytes: 65, accumulationGas: 10'u64, refinementGas: high(uint64),
          historyPeaks: @[], targetSlot: 0'u32,
      withTicket: false, shiftPending: false, guaranteeSlot: 0'u32, refinement: @[], parentPools: @[],
      storeWrites: 1000'u64, completeState: false, serviceNamespaces: @[])

proc authored*(base: OwnedReport, options = signedBlockFixtureConfig()): Context =
  ## Author a signed advancing block (slot 2 by default), then run real disputes/Safrole/assurance processing.
  ## Modes damage one report or parent relation; full headers, signatures and parent roots are recomputed honestly.
  ## Optional ready rows and belt peaks enter the parent; explicit preimage wire enters the child extrinsic before commitment/signing.
  let cfg = config()
  var ancient = default(header.Header)
  ancient.unsigned.epoch = absentEpoch()
  ancient.unsigned.winners = absentWinners()
  let lookup = owner(ancient)
  let lookupHash = array[32, byte](blake2b256(wire(ancient)).value)
  var parent = ancient
  parent.unsigned.slot = HeaderSlot(1)
  parent.unsigned.parent = HeaderParent(lookupHash)
  let parentOwner = owner(parent)
  let parentHash = array[32, byte](blake2b256(wire(parent)).value)
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  let public = array[32, byte](publicKey(key).value)
  var roster = newSeq[StateValidator](6)
  # Match the independent deterministic Ed25519 identities used by the shared test signer.
  for i in 0..<6:
    var seed = default(array[32, byte])
    seed[0] = byte(i+11)
    let ed = importSeed(seed).value
    roster[i].ed25519 = StateEdKey(array[32, byte](publicKey(ed).value))
    roster[i].bandersnatch = StateBsKey(public)
  var pending = roster
  if options.shiftPending:
    # Old active/previous positions remain unchanged while the next epoch receives shifted key identities.
    pending = newSeq[StateValidator](roster.len)
    for index in 0..<pending.len: pending[index] = roster[(index+1) mod roster.len]
  var schedule = newSeq[StateBsKey](12)
  for i in 0..<12: schedule[i] = StateBsKey(public) # Every authored fallback slot has the real seal key.
  # Preserve existing fixtures by default; optional code rebinding happens before any root or signature.
  let selectedBase = if options.accountCode.len == 0: base
    else: withCode(base, options.accountCode) # Bind optional authored code to every signed report and account.
  let sample = reportFor(selectedBase, 0, [options.accumulationGas])
  var entries = entriesFor([sample], transferMinimum = options.accountTransferGas)
  var pools = newSeq[AuthorizerRow](2)
  assert options.poolCopies >= 1 and options.poolCopies <=
      8 # Authored duplicates stay inside the protocol's pool cardinality.
  for i in 0..<2:
    pools[i] = newSeq[AuthorizerHash](options.poolCopies)
    for ordinal in 0..<options.poolCopies: pools[i][ordinal] = ownedReportInfo(
        sample).value.authorizer # Both cores admit the same authenticated authorizer, with optional oldest-only removal witnesses.
  if options.parentPools.len > 0: pools = options.parentPools # Explicit canonical pools enter the original signed parent.
  if options.mode == 1: pools[1] = @[] # Later report fails after the first valid policy record.
  entries[0] = authorizationEntry(AuthorizationKind.Pools, pools, cfg.policy.pools).value
  let history = HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(parentHash),
    state: default(HistoryStateRoot), superPeak: default(HistorySuperPeak), slot: HistorySlot(1),
        packages: @[])], peaks: options.historyPeaks)
  if options.mode != 9: entries.add(historyStateEntry(history,
      cfg.anchors.history).value) # Missing history must not be synthesized.
  if options.mode == 10: entries[^1].value.add(0) # An exact parent value cannot carry a suffix.
  var ringRoot = default(StateRingRoot)
  var ticketWire = @[0'u8]
  if options.withTicket:
    # One genuine RingVRF proof shares the exact committed pending roster and zero parent entropy[2].
    let setup = newSetup(6).value
    var members = newSeq[byte](6*32)
    for index in 0..<6:
      for octet in 0..<32: members[index*32+octet] = public[octet]
    ringRoot = StateRingRoot(array[144, byte](commitRing(setup, members).value))
    var context = default(array[48, byte])
    for index, octet in "jam_ticket_seal": context[index] = byte(octet)
    let proof = signRing(setup, key, 0, members, context, []).value
    var encodedTicket = newSeq[byte](786)
    let writtenTicket = encodeTickets([Ticket(attempt: TicketAttempt(0),
      proof: TicketProof(array[784, byte](proof)))], TicketLimit(3), encodedTicket)
    assert writtenTicket.error == TicketError.None
    encodedTicket.setLen(writtenTicket.written)
    ticketWire = encodedTicket
    close(setup) # Fixed proof/root own no borrowed setup memory.
  entries.add(safroleStateEntry(SafroleState(pending: pending, root: ringRoot,
    schedule: keySchedule(schedule), accumulator: @[]), safrole().state).value)
  entries.add(entropyEntry(default(StateEntropy)))
  for chapter in [ValidatorChapter.Staging, ValidatorChapter.Active, ValidatorChapter.Previous]:
    entries.add(validatorEntry(chapter, (if chapter ==
        ValidatorChapter.Staging: pending else: roster),
      cfg.credentials.assignments.roster).value) # Independent immutable roster entries.
  entries.add(timeEntry(StateTime(1)))
  var judgments = DisputeState()
  var evidence = Disputes(culprits: @[])
  var punished: seq[OffenderKey] = @[]
  if options.withDispute:
    var seedBytes = default(array[32, byte])
    seedBytes[0] = 16
    let seed = importSeed(seedBytes).value
    let publicEd = array[32, byte](publicKey(seed).value)
    let target = default(DisputeHash)
    judgments.reports[JudgmentSet.Bad] = @[target] # Parent already classifies this target as invalid.
    let message = transcript("jam_guarantee", array[32, byte](target))
    punished = @[OffenderKey(publicEd)]
    evidence.culprits = @[Culprit(target: target, key: punished[0],
      signature: DisputeSignature(array[64, byte](sign(seed, message).value)))] # Real new-offender evidence.
  entries.add(disputeStateEntry(judgments, cfg.judgments).value)
  var assignments = newSeq[AvailabilityAssignment](2)
  if options.mode in [7, 11, 12] or options.withAvailable:
    let oldReport = if options.mode == 12: report(selectedBase, 0, default(state_trie.StateRoot),
        parentHash, lookupHash, 0, accumulationGas = options.accumulationGas)
      else: sample # Only mode 12 reuses the incoming package identity in the parent table.
    let prior = certify([oldReport], 1).verifiedGuaranteeAt(0).value
    assignments[0] = presentAssignment(prior, AssignmentSlot(
        1)) # Occupied at slot 2; timeout modes below use slot 6.
  entries.add(availabilityStateEntry(assignments, cfg.packages.availability).value)
  var readyRows = newSeq[ReadyRow](12)
  readyRows[0] = options.ready # Optional already-queued reports enter the signed parent commitment before admission.
  entries.add(readyStateEntry(readyRows, cfg.packages.queues).value)
  var accumulated = newSeq[AccumulatedRow](12)
  if options.mode == 6:
    var duplicate = PackageHash(bytes: default(array[32, byte]))
    duplicate.bytes[0] = 11
    accumulated[11] = @[duplicate] # A later incoming package duplicates parent pipeline state.
  entries.add(accumulatedStateEntry(accumulated, cfg.packages.queues).value)
  if options.mode == 13: entries.delete(entries.len-2) # Parent ready chapter is mandatory even on an empty batch.
  if options.completeState:
    entries.add(outputLogEntry([], OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(
        1))).value) # Author canonical empty C16 before commitments and signatures.
  else:
    entries.add(StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 4,
      2])) # Existing scoped fixtures preserve the opaque rollback sentinel by default.
  # Extra chapters enter the parent root committed by the signed candidate and report guarantees.
  for entry in options.extra: entries.add(entry)
  if options.serviceNamespaces.len > 0:
    assert options.completeState # Scoped rollback sentinels never enter complete logical fixtures.
    seedServiceNamespaces(entries, options.serviceNamespaces, ByteLimit(
        options.namespaceValueBytes))
  var bounds = limits()
  bounds.writeValueBytes = ByteLimit(options.maxWriteBytes)
  bounds.writes = ElementLimit(options.storeWrites) # Optional inherited batch limits enter the original store before any stage.
  let created = newStateStore(entries, bounds)
  assert created.error == StateStoreError.None, $created.error
  var state = created.value
  let root = state.snapshot.value.commitment.root
  let target = if options.targetSlot != 0: options.targetSlot else: (if options.mode in [11,
      12]: 6'u32 else: 2'u32)
  var children = newSeq[OwnedReport](options.reports)
  for i in 0..<options.reports: children[i] = report(selectedBase, i, root, parentHash, lookupHash,
      options.mode, options.refinementGas, options.refinement,
      options.accumulationGas) # Signed metadata includes corrected parent root and authored refinement work.
  var guarantees = newSeq[Guarantee](options.reports)
  let signedSlot = if options.guaranteeSlot == 0: target else: options.guaranteeSlot
  let signed = certify(children, signedSlot, punished)
  for i in 0..<options.reports: guarantees[i] = signed.verifiedGuaranteeAt(
      i).value # Real Ed25519 signatures, never observer successes.
  if options.mode == 8: guarantees[^1].credentials[0].signature = default(
      GuaranteeSignature) # Later invalid credential.
  var encoded = newSeq[byte](100000)
  let written = encodeGuarantees(guarantees, cfg.packages.availability.guarantee, encoded)
  assert written.error == GuaranteeError.None
  encoded.setLen(written.value)
  var body = ticketWire
  if options.preimageWire.len == 0:
    body.add(0'u8) # Preserve the original empty preimage extrinsic by default.
  else:
    for octet in options.preimageWire: body.add(octet) # Explicit authored preimages enter the real signed extrinsic commitment.
  for octet in encoded: body.add(octet) # Copy complete guarantee encoding.
  if options.withAvailable:
    var votes = newSeq[Assurance](5)
    # Five genuine parent-validator signatures assure the old core-zero report before new assignments.
    for i in 0..<5:
      var seedBytes = default(array[32, byte])
      seedBytes[0] = byte(i+11)
      var bits = default(AssuranceBits)
      bits.bytes[0] = 1
      let message = array[45, byte](assuranceMessage(AssuranceParent(parentHash), bits, CoreCount(2)).value)
      votes[i] = Assurance(anchor: AssuranceAnchor(bytes: parentHash), bits: bits,
        validator: ValidatorIndex(i), signature: AssuranceSignature(bytes: array[64, byte](
          sign(importSeed(seedBytes).value, message).value)))
    var assuranceBytes = newSeq[byte](1000)
    let assuranceSize = encodeAssurances(votes, AssuranceConfig(cores: CoreCount(2),
      validators: ValidatorCount(6)), assuranceBytes)
    assert assuranceSize.error == AssuranceError.None
    for i in 0..<assuranceSize.written: body.add(assuranceBytes[i]) # Exact canonical voted payload.
  else:
    body.add(0'u8) # Empty assurances preserve the independently controlled timeout path.
  var disputeBytes = newSeq[byte](1000)
  let disputeSize = encodeDisputes(evidence, DisputeConfig(validators: ValidatorCount(6),
      maxBytes: ByteLimit(1000)), disputeBytes)
  assert disputeSize.error == DisputeError.None
  for i in 0..<disputeSize.value: body.add(disputeBytes[i]) # Complete exact disputes, including any new offender.
  let extrinsic = decodeExtrinsic(body, frame().frame).value.owner
  var candidate = ancient
  candidate.unsigned.parent = HeaderParent(parentHash)
  candidate.unsigned.priorState = PriorStateRoot(array[32, byte](root))
  candidate.unsigned.extrinsics = ExtrinsicRoot(array[32, byte](extrinsicCommitment(extrinsic,
      frame().frame.maxBytes).value))
  candidate.unsigned.slot = HeaderSlot(target)
  if target >= 12:
    # With unchanged staging/pending rosters and zero parent entropy, this is the exact rotated marker.
    var epochKeys = newSeq[EpochValidator](pending.len)
    for index in 0..<epochKeys.len:
      epochKeys[index] = EpochValidator(bandersnatch: HeaderBsKey(public),
        ed25519: HeaderEdKey(array[32, byte](pending[index].ed25519)))
    candidate.unsigned.epoch = presentEpoch(default(EpochEntropy), default(TicketsEntropy), epochKeys)
  if options.withDispute:
    candidate.unsigned.offenders = @[HeaderEdKey(array[32, byte](punished[
        0]))] # Signed literal marker matches this block's evidence.
  let input = transcript("jam_fallback_seal", default(array[32, byte]))
  let provisional = sign(key, input, []).value
  let output = array[32, byte](verify(BsPublicKey(public), provisional, input, []).value)
  candidate.unsigned.entropyProof = HeaderEntropyProof(array[96, byte](sign(key, transcript(
      "jam_entropy", output), []).value))
  var unsigned = newSeq[byte](100000)
  let unsignedSize = encodeUnsignedHeader(candidate.unsigned, cfg.ancestors.header, unsigned).value
  unsigned.setLen(unsignedSize)
  candidate.seal = HeaderSeal(array[96, byte](sign(key, input, unsigned).value))
  close(key)
  var blockBytes = wire(candidate)
  for octet in body: blockBytes.add(octet) # Append exactly the committed body.
  let blockOwner = decodeBlock(blockBytes, frame().frame).value.owner
  let original = state
  let completed = stage(state, blockOwner, parentOwner)
  assert completed.error == BlockTransitionError.None, $completed.error
  result = Context(staged: completed, older: @[lookup], original: original, candidate: blockOwner,
      parent: parentOwner, source: entries)

