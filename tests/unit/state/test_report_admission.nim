# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed authored block composition plus unchanged empty-report traces; every verdict belongs to native tests.
import std/[assertions, envvars, strutils, syncio, sequtils]
import ../../../src/state/[report_admission, report_assignments, report_policy, report_anchors,
  report_packages, guarantee_credentials, block_transition, block_admission, store,
  safrole_transition, disputes, availability]
import ../../../src/codec/[block_codec, header, bounded, guarantees, assurances, state_safrole,
  state_consensus, state_disputes, state_layout, state_trie, state_history, state_availability,
  state_workqueues, state_authorization, tickets, report_owned, owned, work_report, composite]
import ../../../src/crypto/[primitives, extrinsic_commitment]
import ../../../src/bandersnatch/bandersnatch
import ../../support/[report_context, arc_evidence]

## Controlled backend refusal never replaces successful verification.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Keep all stage domains equal while independently bounding each chapter and ancestor chain.
proc config(): ReportAdmissionConfig =
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

## The same finite profile applies to both block commitments and stage execution.
proc frame(): BlockAdmissionConfig =
  BlockAdmissionConfig(frame: FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      epochSlots: EpochSlots(12),
    ticketLimit: TicketLimit(3), maxBytes: ByteLimit(2000000), preimages: PreimageLimits(
        items: ElementLimit(100),
      perBlob: ByteLimit(100000), totalBlobBytes: ByteLimit(100000))),
          maxParentHeaderBytes: ByteLimit(100000))

## Full coordinator policy keeps non-epoch authored fixtures free of unnecessary ring setup.
proc safrole(): SafroleTransitionConfig =
  SafroleTransitionConfig(state: SafroleStateConfig(validators: credentialConfig(
      2).assignments.roster,
    epochSlots: EpochSlots(12), maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(2000000)),
    tailStart: EpochSlots(10), blockTickets: TicketLimit(3), offenders: ElementLimit(10000),
    maxHeaderBytes: ByteLimit(2000000), maxMarkerBytes: ByteLimit(2000000))

## Execute only real coordinator entry points; no forged successful stage value enters report admission.
proc stage(state: var StateStore, candidate: OwnedBlock,
    parent: OwnedHeader): BlockTransitionResult =
  let cfg = config()
  let disputes = DisputesConfig(rosters: cfg.credentials.assignments.roster, epochSlots: EpochSlots(12),
    state: cfg.judgments, availability: cfg.packages.availability, maxExtrinsicBytes: ByteLimit(2000000))
  advanceBlockState(state, candidate, parent, frame(), disputes, safrole(),
    AvailabilityTransitionConfig(rosters: cfg.credentials.assignments.roster,
      assignments: cfg.packages.availability, availableReports: ElementLimit(2)))

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
    32, byte], mode: int): OwnedReport =
  let raw = reportBytes(reportFor(base, core, [10'u64]))
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
  value.prerequisiteCount = 0
  value.lookupCount = 0
  if mode == 3: value.header.stateRoot.bytes[0] = value.header.stateRoot.bytes[
      0] xor 1 # Corrected recent tuple must match all fields.
  if mode == 4: value.header.lookupStateRoot.bytes[0] = 1 # Historical child commits a different root.
  var output = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(value, raw, 2, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 2).value

## Scoped fixture retains a genuine successful/refused coordinator result and supplied older headers only.
type Context = object
  staged: BlockTransitionResult
  older: seq[OwnedHeader]

## Author a signed slot-2 block, then run real disputes/Safrole/assurance processing before report checks.
## Modes damage one report or parent relation; full headers, signatures and parent roots are recomputed honestly.
proc authored(base: OwnedReport, mode = 0, reports = 2): Context =
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
  var schedule = newSeq[StateBsKey](12)
  for i in 0..<12: schedule[i] = StateBsKey(public) # Every authored fallback slot has the real seal key.
  let sample = reportFor(base, 0, [10'u64])
  var entries = entriesFor([sample])
  var pools = newSeq[AuthorizerRow](2)
  for i in 0..<2: pools[i] = @[ownedReportInfo(sample).value.authorizer] # Both cores admit this authorizer.
  if mode == 1: pools[1] = @[] # Later report fails after the first valid policy record.
  entries[0] = authorizationEntry(AuthorizationKind.Pools, pools, cfg.policy.pools).value
  let history = HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(parentHash),
    state: default(HistoryStateRoot), superPeak: default(HistorySuperPeak), slot: HistorySlot(1),
        packages: @[])], peaks: @[])
  if mode != 9: entries.add(historyStateEntry(history,
      cfg.anchors.history).value) # Missing history must not be synthesized.
  if mode == 10: entries[^1].value.add(0) # An exact parent value cannot carry a suffix.
  entries.add(safroleStateEntry(SafroleState(pending: roster, root: default(StateRingRoot),
    schedule: keySchedule(schedule), accumulator: @[]), safrole().state).value)
  entries.add(entropyEntry(default(StateEntropy)))
  for chapter in [ValidatorChapter.Staging, ValidatorChapter.Active, ValidatorChapter.Previous]:
    entries.add(validatorEntry(chapter, roster, cfg.credentials.assignments.roster).value) # Independent immutable roster entries.
  entries.add(timeEntry(StateTime(1)))
  entries.add(disputeStateEntry(DisputeState(), cfg.judgments).value)
  var assignments = newSeq[AvailabilityAssignment](2)
  if mode in [7, 11, 12]:
    let oldReport = if mode == 12: report(base, 0, default(state_trie.StateRoot), parentHash,
        lookupHash, 0)
      else: sample # Only mode 12 reuses the incoming package identity in the parent table.
    let prior = certify([oldReport], 1).verifiedGuaranteeAt(0).value
    assignments[0] = presentAssignment(prior, AssignmentSlot(
        1)) # Occupied at slot 2; timeout modes below use slot 6.
  entries.add(availabilityStateEntry(assignments, cfg.packages.availability).value)
  entries.add(readyStateEntry(newSeq[ReadyRow](12), cfg.packages.queues).value)
  var accumulated = newSeq[AccumulatedRow](12)
  if mode == 6:
    var duplicate = PackageHash(bytes: default(array[32, byte]))
    duplicate.bytes[0] = 11
    accumulated[11] = @[duplicate] # A later incoming package duplicates parent pipeline state.
  entries.add(accumulatedStateEntry(accumulated, cfg.packages.queues).value)
  if mode == 13: entries.delete(entries.len-2) # Parent ready chapter is mandatory even on an empty batch.
  let created = newStateStore(entries, limits())
  assert created.error == StateStoreError.None, $created.error
  var state = created.value
  let root = state.snapshot.value.commitment.root
  let target = if mode in [11, 12]: 6'u32 else: 2'u32
  var children = newSeq[OwnedReport](reports)
  for i in 0..<reports: children[i] = report(base, i, root, parentHash, lookupHash,
      mode) # Signed metadata includes corrected parent root.
  var guarantees = newSeq[Guarantee](reports)
  let signed = certify(children, target)
  for i in 0..<reports: guarantees[i] = signed.verifiedGuaranteeAt(
      i).value # Real Ed25519 signatures, never observer successes.
  if mode == 8: guarantees[^1].credentials[0].signature = default(GuaranteeSignature) # Later invalid credential.
  var encoded = newSeq[byte](100000)
  let written = encodeGuarantees(guarantees, cfg.packages.availability.guarantee, encoded)
  assert written.error == GuaranteeError.None
  encoded.setLen(written.value)
  var body = @[0'u8, 0]
  for octet in encoded: body.add(octet) # Copy complete guarantee encoding.
  for i in 0..<4: body.add(0'u8) # Empty assurances and three empty dispute families.
  let extrinsic = decodeExtrinsic(body, frame().frame).value.owner
  var candidate = ancient
  candidate.unsigned.parent = HeaderParent(parentHash)
  candidate.unsigned.priorState = PriorStateRoot(array[32, byte](root))
  candidate.unsigned.extrinsics = ExtrinsicRoot(array[32, byte](extrinsicCommitment(extrinsic,
      frame().frame.maxBytes).value))
  candidate.unsigned.slot = HeaderSlot(target)
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
  let completed = stage(state, blockOwner, parentOwner)
  assert completed.error == BlockTransitionError.None, $completed.error
  result = Context(staged: completed, older: @[lookup])

## Compare canonical state root and every known byte after pure planning, not just C(10).
proc unchanged(before, after: StateStoreSnapshot) =
  assert array[32, byte](before.commitment.root) == array[32, byte](after.commitment.root)
  for number in [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15]:
    let key = chapterKey(StateChapter(number))
    assert before.lookup(key).value.bytes == after.lookup(key).value.bytes # No report-stage writes at all.

## Repeated complete success and later-policy refusal must retire every retained plan and input capture.
proc cycle(context: Context, expected: ReportAdmissionError) =
  assert planBlockReports(context.staged, context.older, config()).error == expected

## Compose every report check, retain exact block/source owners and reject cross-context substitutes by API design.
proc boundaries(base: OwnedReport) =
  let context = authored(base)
  let original = context.staged.value.snapshot
  let admitted = planBlockReports(context.staged, context.older, config())
  assert admitted.error == ReportAdmissionError.None, $admitted.error
  let certificate = admitted.value
  assert certificate.reportCredentials.value.verifiedGuaranteeCount.value == 2
  let assignments = certificate.reportAssignments.value.reportAssignmentState.value
  assert availabilityInfo(assignments).value.present == 2
  assert uint32(availabilityAt(assignments, AssignmentCoreIndex(0)).value.registered) == 2
  let actual = certificate.reportBlockStage.value
  unchanged(original, actual.value.snapshot)
  unchanged(context.staged.value.admitted.admittedState, actual.value.admitted.admittedState)
  let first = certificate.reportCredentials.value.verifiedGuaranteeAt(0).value.report
  let fields = ownedReportInfo(first).value.header
  assert fields.stateRoot.bytes == array[32, byte](
      context.staged.value.admitted.admittedState.commitment.root) # Real correction is necessary: stored latest root is zero.
  let missing = BlockTransitionResult()
  assert planBlockReports(missing, [], config()).error == ReportAdmissionError.InvalidTransition
  assert default(AdmittedReports).reportAssignments.error == ReportAdmissionError.Uninitialized
  assert default(AdmittedReports).reportCredentials.error == ReportAdmissionError.Uninitialized
  assert default(AdmittedReports).reportBlockStage.error == ReportAdmissionError.Uninitialized
  # Independent domain substitutions fail before cryptographic checks.
  for mode in 0..<6:
    var bad = config()
    case mode
    of 0: bad.credentials.assignments.roster.cores = CoreCount(3) # Different roster core domain.
    of 1: bad.credentials.assignments.epochSlots = EpochSlots(24) # Different credential epoch.
    of 2: bad.packages.queues.epochSlots = EpochSlots(24) # Different pipeline ring extent.
    of 3: bad.ancestors.header.authorValidators = ValidatorCount(9) # Different header population ceiling.
    of 4: bad.packages.availability.guarantee.validators = ValidatorCount(9) # Different C(10) domain.
    else: bad.anchors.history.cores = CoreCount(3) # Different history domain.
    assert planBlockReports(context.staged, context.older, bad).error ==
        ReportAdmissionError.InvalidConfig
  var small = config()
  small.credentials.assignments.roster.maxBytes = ByteLimit(1)
  assert planBlockReports(context.staged, context.older, small).error ==
      ReportAdmissionError.LimitExceeded
  small = config()
  small.ancestors.headers = ElementLimit(1)
  let bounded = planBlockReports(context.staged, context.older, small)
  assert bounded.error == ReportAdmissionError.AnchorFailure and bounded.anchorError ==
      ReportAnchorError.LimitExceeded
  let noAncestor = planBlockReports(context.staged, [], config())
  assert noAncestor.error == ReportAdmissionError.AnchorFailure and noAncestor.anchorError ==
      ReportAnchorError.MissingLookupAnchor
  let fork = planBlockReports(context.staged, [context.staged.value.admitted.admittedParent],
      config())
  assert fork.error == ReportAdmissionError.AnchorFailure and fork.anchorError ==
      ReportAnchorError.BrokenAncestry
  # Later-stage refusals preserve the complete original staged map.
  for mode in [1, 3, 4, 6, 7, 8, 9, 10, 13]:
    let broken = authored(base, mode)
    let outcome = planBlockReports(broken.staged, broken.older, config())
    case mode
    of 1:
      assert outcome.error == ReportAdmissionError.PolicyFailure and outcome.policyError ==
          ReportPolicyError.Unauthorized # First report already passed.
    of 3:
      assert outcome.error == ReportAdmissionError.AnchorFailure and outcome.anchorError ==
          ReportAnchorError.InvalidRecentAnchor # Cannot supply a fabricated corrected history.
    of 4:
      assert outcome.error == ReportAdmissionError.AnchorFailure and outcome.anchorError ==
          ReportAnchorError.WrongLookupState # Child root, not loose lookup metadata.
    of 6:
      assert outcome.error == ReportAdmissionError.PackageFailure and outcome.packageError ==
          ReportPackageError.DuplicatePackage # Parent last accumulated row remains relevant.
    of 7:
      assert outcome.error == ReportAdmissionError.AssignmentFailure and outcome.assignmentError ==
          ReportAssignmentError.OccupiedCore # Actual post-assurance table still occupied.
    of 8:
      assert outcome.error == ReportAdmissionError.CredentialFailure and
          outcome.credentialError.error ==
          GuaranteeCredentialError.InvalidSignature # Reverify this block's exact credentials.
    of 9:
      assert outcome.error == ReportAdmissionError.MissingState # Missing parent history is not empty history.
    of 13:
      assert outcome.error == ReportAdmissionError.PackageFailure and outcome.packageError ==
          ReportPackageError.MissingState # No omitted parent-pipeline fallback.
    else:
      assert outcome.error == ReportAdmissionError.InvalidState # Exact history refuses suffix.
  let expired = authored(base, 11)
  assert availabilityInfo(expired.staged.value.availability.assuredAssignments).value.present == 0
  assert planBlockReports(expired.staged, expired.older, config()).error ==
      ReportAdmissionError.None # Use actual timeout-cleared table, not parent C(10).
  let duplicateExpired = authored(base, 12)
  assert availabilityInfo(duplicateExpired.staged.value.availability.assuredAssignments).value.present == 0
  let duplicate = planBlockReports(duplicateExpired.staged, duplicateExpired.older, config())
  assert duplicate.error == ReportAdmissionError.PackageFailure and duplicate.packageError ==
      ReportPackageError.DuplicatePackage # A freed core does not erase parent package exclusion.
  let empty = authored(base, reports = 0)
  assert planBlockReports(empty.staged, empty.older, config()).error ==
      ReportAdmissionError.None # Empty batch still binds all context.
  failHash(1)
  let backend = planBlockReports(context.staged, context.older, config())
  assert backend.error == ReportAdmissionError.CredentialFailure and
      backend.credentialError.error == GuaranteeCredentialError.AssignmentFailure
  failHash(0)
  var detached = certificate.reportAssignments.value.reportAssignmentEntry.value
  detached.value[0] = detached.value[0] xor 1
  assert availabilityInfo(certificate.reportAssignments.value.reportAssignmentState.value).value.present == 2
  let refused = authored(base, 1)
  cycle(context, ReportAdmissionError.None)
  cycle(refused, ReportAdmissionError.PolicyFailure)
  let before = getOccupiedMem()
  for i in 0..<1000:
    if i mod 2 == 0: cycle(context, ReportAdmissionError.None) # Retire complete retained chain.
    else: cycle(refused, ReportAdmissionError.PolicyFailure) # Retire successful credential work before later refusal.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("report_admission", 1000, before, after)

## Reuse unchanged published signed blocks, explicitly limited to their empty report batches.
proc published() {.raises.} =
  var count = 0
  for line in readFile(getEnv("RAGNAROK_BLOCK_ADMISSION")).splitLines:
    if line.len == 0: continue # Terminal newline is not another case.
    let fields = line.splitWhitespace
    var entries: seq[StateEntry] = @[]
    for pair in fields[3].split(','):
      let parts = pair.split('=')
      let keyBytes = unhex(parts[0])
      var key = default(array[31, byte])
      for i in 0..<31: key[i] = keyBytes[i] # Exact original key identity.
      entries.add(StateEntry(key: StateKey(key), value: unhex(parts[1])))
    let bounds = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(100000),
        perValue: ByteLimit(20000000),
      totalValueBytes: ByteLimit(100000000), nodes: TrieNodeLimit(1000000)), writes: ElementLimit(
          5), writeValueBytes: ByteLimit(20000000))
    let created = newStateStore(entries, bounds)
    assert created.error == StateStoreError.None, fields[0] & " " & $created.error
    var state = created.value
    let candidate = decodeBlock(unhex(fields[1]), frame().frame).value.owner
    let parent = decodeHeader(unhex(fields[2]), config().ancestors.header).value.owner
    let staged = stage(state, candidate, parent)
    assert staged.error == BlockTransitionError.None
    let outcome = planBlockReports(staged, [], config())
    assert outcome.error == ReportAdmissionError.None, fields[0] & " " & $outcome.error
    assert outcome.value.reportCredentials.value.verifiedGuaranteeCount.value == 0
    inc count
  assert count == 10

## Missing fixtures fail, rather than quietly skipping authored or external evidence.
proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # Canonical template hash is checked by fixture preparation.
  boundaries(decodeOwnedReport(bytes, 341).value)
  published()
  echo "PASS report admission: bound block stages, corrected history, exact credentials and rollback-free planning"
try:
  main() # Every implementation verdict remains native.
except:
  quit(2) # Missing trusted fixture transport cannot become success.
