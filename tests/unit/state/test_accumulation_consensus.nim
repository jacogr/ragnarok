# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_consensus_arc_release"}

## Real block prefixes and completed accumulation compose exact seven-chapter state without losing either source's effects.

import std/[assertions, envvars, syncio]
import ../../../src/state/accumulation/[consensus as accumulation_consensus,
    authorization as accumulation_authorization, preimages as accumulation_preimages,
    activity as accumulation_activity, validators as accumulation_validators,
    times as accumulation_times, statistics as accumulation_statistics,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../../../src/state/report/[admission as report_admission, assignments as report_assignments]
import ../../../src/state/guarantee_credentials
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/core/service_activity as core_service_activity
import ../../../src/state/[preimages, authorization, store]
import ../../../src/codec/[bounded, composite, header, report_owned, guarantees, assurances]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    accounts as state_accounts, service_values as state_service_values]
import ../../../src/crypto/primitives
import ../../support/[accumulation_activity_context, accumulation_provision_integration,
  report_context, arc_evidence]

# Inject only after genuine signed stages, report planning, guests and bookkeeping are complete.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc limits(): AccumulationConsensusLimits =
  ## Explicit small copy budgets exceed the actual seven tiny-profile chapters independently of store limits.
  AccumulationConsensusLimits(chapterBytes: ByteLimit(10000), totalBytes: ByteLimit(50000))

proc authorization(source: PreparedAccumulationValidators): PreparedAccumulationAuthorization =
  ## Public constructors retain real earlier authority and effects; no successful result or owner is forged.
  let activity = prepareAccumulationActivity(source, AccumulationActivityConfig(
    componentBytes: ByteLimit(1024), preimages: PreimageLimits(items: ElementLimit(3),
      perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(4)), incoming: ElementLimit(2),
    available: ElementLimit(1), digests: ElementLimit(2), assurances: ElementLimit(5),
    provisions: ElementLimit(2), accumulation: ElementLimit(2), services: ElementLimit(2),
    activityBytes: ByteLimit(4096))).value
  let lookup = prepareAccumulationPreimages(activity, AccumulationPreimageLimits(
      items: ElementLimit(3),
    bytes: ByteLimit(4))).value
  prepareAccumulationAuthorization(lookup, AccumulationAuthorizationLimits(guarantees: ElementLimit(2),
    inputHashes: ElementLimit(160), inputBytes: ByteLimit(5120), outputHashes: ElementLimit(16),
    outputBytes: ByteLimit(514))).value

proc admission(source: PreparedAccumulationAuthorization): AdmittedReports =
  ## Retain the authenticated original block/report owner through the exact successful source graph.
  source.accumulationAuthorizationSource.value.accumulationPreimagesSource.value.accumulationActivitySource.value.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value.accumulationAdmission.value

proc fixedSlot(slot: uint32): seq[byte] =
  ## Literal E4 time framing is independent of the state-time codec and private overlay implementation.
  result = @[]
  for shift in 0..<4: result.add(byte((slot shr (8*shift)) and 255))

proc assignments(owner: AdmittedReports, slot: uint32): seq[byte] =
  ## Independent C(10) composition uses only verified incoming children and literal option/registration framing.
  let credentials = owner.reportCredentials.value
  result = @[]
  for core in 0..<2:
    var present = false
    for index in 0..<credentials.verifiedGuaranteeCount.value:
      let guarantee = credentials.verifiedGuaranteeAt(index).value
      if uint64(guarantee.report.ownedReportInfo.value.core) == uint64(core):
        assert not present
        present = true
        result.add(1)
        let encoded = encodeGuaranteeValue(guarantee, GuaranteeConfig(cores: CoreCount(2),
          validators: ValidatorCount(6), maxBytes: ByteLimit(100000))).value
        for octet in encoded: result.add(octet) # Existing standalone child framing remains independent of the assignment planner.
        for octet in fixedSlot(slot): result.add(octet) # Registration is a second E4 timestamp, not the guarantee's slot.
    if not present: result.add(0) # Authored fixtures have no surviving old assignments after assurance clearing.

proc valueEntry(service: uint32, bytes: seq[byte]): StateEntry =
  ## Derive only the namespace key; raw values and complete expected-map enumeration are test-owned.
  let hash = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  servicePreimageEntry(ServiceIndex(service), hash, bytes,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(bytes.len)))).value

proc oracle(fixture: ActivityFixture, source: PreparedAccumulationAuthorization,
    assigned: seq[byte], blobs, provided: bool): StateStoreSnapshot =
  ## Rebuild every known key from the prior except six stage entries and independently framed final C(10).
  let prior = source.accumulationAuthorizationState.value
  let stage = admission(source).reportBlockStage.value.value.snapshot
  var entries: seq[StateEntry] = @[]
  for original in fixture.entries:
    var value = prior.lookup(original.key).value.bytes
    for number in [4'u8, 5, 6, 8, 9, 11]:
      if array[31, byte](original.key) == array[31, byte](chapterKey(StateChapter(number))):
        value = stage.lookup(original.key).value.bytes # Exact immutable authenticated stage encoding is the authority for these chapters.
    if array[31, byte](original.key) == array[31, byte](chapterKey(StateChapter(
        10))): value = assigned
    entries.add(StateEntry(key: original.key, value: value))
  entries.add(StateEntry(key: chapterKey(StateChapter(16)),
    value: prior.lookup(chapterKey(StateChapter(16))).value.bytes)) # Finalization alone added this absent original chapter.
  if blobs:
    for entry in [valueEntry(42, @[73'u8]), valueEntry(99, @[]), valueEntry(99, @[81'u8, 82, 83])]:
      entries.add(StateEntry(key: entry.key, value: prior.lookup(
          entry.key).value.bytes)) # Earlier lookup/guest effects are preserved exactly.
  if provided: entries.add(valueEntry(99, @[81'u8])) # The guest also provided one independent non-lookup pair.
  assert entries.len == prior.commitment.entries, "known keys exhaust the complete source map"
  newStateStore(entries, report_context.limits()).value.snapshot.value

proc witness(base: OwnedReport, uses = 0, available = false, blobs = false, provided = false,
    disputed = false, rotated = false, ticket = false): PreparedAccumulationConsensus =
  ## Real signed consensus changes and actual earlier accumulation effects coexist in the final private complete map.
  let slot = if rotated: 12'u32 else: 2'u32
  let fixture = activityFixture(base, guarantees = uses, available = available, blobs = blobs,
    provided = provided, withDispute = disputed, slot = slot, shiftPending = rotated,
    withTicket = ticket)
  let source = authorization(fixture.source)
  let prior = source.accumulationAuthorizationState.value
  let owner = admission(source)
  let stage = owner.reportBlockStage.value.value.snapshot
  let assigned = assignments(owner, slot)
  let expected = oracle(fixture, source, assigned, blobs, provided)
  assert owner.reportAssignments.value.reportAssignmentByteLength.value == assigned.len
  let resultOwner = prepareAccumulationConsensus(source, limits())
  assert resultOwner.error == AccumulationConsensusError.None
  result = resultOwner.value
  let state = result.accumulationConsensusState.value
  let facts = result.accumulationConsensusInfo.value
  assert uint32(facts.slot) == slot and facts.chapters == 7
  assert array[32, byte](state.commitment.root) == array[32, byte](expected.commitment.root)
  assert state.commitment.entries == prior.commitment.entries
  assert not sameStateSnapshot(prior, state)
  assert sameStateSnapshot(prior, result.accumulationConsensusSource.value.accumulationAuthorizationState.value)
  var bytes = assigned.len
  for number in [4'u8, 5, 6, 8, 9, 11]:
    let key = chapterKey(StateChapter(number))
    assert state.lookup(key).value.bytes == stage.lookup(key).value.bytes
    bytes += stage.lookup(key).value.byteLength # Tiny authored fixture sizes independently freeze the complete copied extent.
  assert facts.bytes == bytes
  assert state.lookup(chapterKey(StateChapter(10))).value.bytes == assigned
  assert state.lookup(chapterKey(StateChapter(11))).value.bytes == fixedSlot(slot)
  assert prior.lookup(chapterKey(StateChapter(11))).value.bytes == fixedSlot(1), "accumulation still retained original parent time"
  assert state.lookup(chapterKey(StateChapter(6))).value.bytes != prior.lookup(chapterKey(
      StateChapter(6))).value.bytes
  for number in [1'u8, 2, 3, 7, 12, 13, 14, 15, 16, 250]:
    let key = chapterKey(StateChapter(number))
    assert state.lookup(key).value.bytes == prior.lookup(key).value.bytes, "accumulation-owned chapters are not overwritten by the stage map"
  if uses > 0:
    assert stage.lookup(chapterKey(StateChapter(10))).value.bytes != assigned, "final incoming assignments replace post-assurance vacancies"
  if available:
    assert prior.lookup(chapterKey(StateChapter(10))).value.bytes != assigned, "original assigned report is actually cleared"
  if disputed:
    assert state.lookup(chapterKey(StateChapter(5))).value.bytes != prior.lookup(chapterKey(
        StateChapter(5))).value.bytes
  if rotated:
    assert state.lookup(chapterKey(StateChapter(8))).value.bytes != prior.lookup(chapterKey(
        StateChapter(8))).value.bytes
  if ticket:
    assert state.lookup(chapterKey(StateChapter(4))).value.bytes != prior.lookup(chapterKey(
        StateChapter(4))).value.bytes
  let retry = prepareAccumulationConsensus(source, limits()).value.accumulationConsensusState.value
  assert array[32, byte](retry.commitment.root) == array[32, byte](state.commitment.root)

proc policies(source: PreparedAccumulationAuthorization) =
  ## Exact copy extents are read before fault injection; one-below policies refuse without hashing or partial publication.
  let owner = admission(source)
  let stage = owner.reportBlockStage.value.value.snapshot
  var total = owner.reportAssignments.value.reportAssignmentByteLength.value
  var largest = total
  for number in [4'u8, 5, 6, 8, 9, 11]:
    let size = stage.lookup(chapterKey(StateChapter(number))).value.byteLength
    total += size
    largest = max(largest, size)
  let exact = AccumulationConsensusLimits(chapterBytes: ByteLimit(uint64(largest)),
    totalBytes: ByteLimit(uint64(total)))
  for mode in 0..<2:
    var short = exact
    if mode == 0: short.chapterBytes = ByteLimit(uint64(largest-1))
    else: short.totalBytes = ByteLimit(uint64(total-1)) # The final C(10) pushes the preflight over its aggregate ceiling.
    failHash(1)
    assert prepareAccumulationConsensus(source, short).error ==
        AccumulationConsensusError.LimitExceeded
    assert hashCalls() == 0
  failHash(0)
  assert prepareAccumulationConsensus(source, exact).error == AccumulationConsensusError.None
  assert prepareAccumulationConsensus(source, AccumulationConsensusLimits(chapterBytes: ByteLimit(
      high(uint64)),
    totalBytes: ByteLimit(high(uint64)))).error == AccumulationConsensusError.None

proc backend(source: PreparedAccumulationAuthorization) =
  ## First and final private Merkle refusal preserve both the original parent-backed accumulator and retained authenticated prefix.
  let prior = source.accumulationAuthorizationState.value
  let staged = admission(source).reportBlockStage.value.value.snapshot
  let root = array[32, byte](prior.commitment.root)
  let stagedRoot = array[32, byte](staged.commitment.root)
  failHash(0)
  discard prepareAccumulationConsensus(source, limits()).value
  let total = hashCalls()
  assert total > 1
  for after in [0.cint, total-1]:
    failAfter(after)
    let refused = prepareAccumulationConsensus(source, limits())
    assert refused.error == AccumulationConsensusError.StateFailure
    assert refused.stateError == StateStoreError.BackendFailure
    assert array[32, byte](source.accumulationAuthorizationState.value.commitment.root) == root
    assert array[32, byte](admission(source).reportBlockStage.value.value.snapshot.commitment.root) == stagedRoot
    assert prior.lookup(chapterKey(StateChapter(11))).value.bytes == fixedSlot(1)
  failHash(0)
  assert prepareAccumulationConsensus(source, limits()).error == AccumulationConsensusError.None

proc cycle(source: PreparedAccumulationAuthorization) =
  ## Scoped success and both late-stage refusals drop every derived map before the next iteration.
  failHash(0)
  let candidate = prepareAccumulationConsensus(source, limits()).value
  assert candidate.accumulationConsensusInfo.value.chapters == 7
  let total = hashCalls()
  failAfter(0)
  assert prepareAccumulationConsensus(source, limits()).stateError == StateStoreError.BackendFailure
  failAfter(total-1)
  assert prepareAccumulationConsensus(source, limits()).stateError == StateStoreError.BackendFailure
  failHash(0)

proc main() {.raises.} =
  ## Native launch supplies pinned report bytes; every scenario runs real block and accumulation preparation.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  discard witness(base)
  discard witness(base, uses = 2)
  discard witness(base, available = true)
  discard witness(base, uses = 2, available = true, blobs = true, provided = true)
  discard witness(base, uses = 2, disputed = true)
  discard witness(base, rotated = true)
  discard witness(base, ticket = true)
  let source = authorization(activityFixture(base, guarantees = 2, blobs = true).source)
  policies(source)
  backend(source)
  let capped = authorization(activityFixture(base, storeWrites = 6).source)
  let cappedRoot = array[32, byte](capped.accumulationAuthorizationState.value.commitment.root)
  failHash(1)
  let refused = prepareAccumulationConsensus(capped, limits())
  assert refused.error == AccumulationConsensusError.StateFailure
  assert refused.stateError == StateStoreError.LimitExceeded, "seven Puts retain the inherited six-write store ceiling"
  assert hashCalls() == 0
  assert array[32, byte](capped.accumulationAuthorizationState.value.commitment.root) == cappedRoot
  assert prepareAccumulationConsensus(default(PreparedAccumulationAuthorization), limits()).error ==
      AccumulationConsensusError.InvalidSource
  assert hashCalls() == 0
  failHash(0)
  assert default(ReportAssignmentPlan).reportAssignmentByteLength.error ==
      ReportAssignmentError.Uninitialized
  let empty = default(PreparedAccumulationConsensus)
  assert empty.accumulationConsensusSource.error == AccumulationConsensusError.Uninitialized
  assert empty.accumulationConsensusInfo.error == AccumulationConsensusError.Uninitialized
  assert empty.accumulationConsensusState.error == AccumulationConsensusError.Uninitialized
  var retained = default(PreparedAccumulationConsensus)
  block:
    let local = authorization(activityFixture(base, guarantees = 2).source)
    retained = prepareAccumulationConsensus(local, limits()).value
  var facts = retained.accumulationConsensusInfo.value
  facts.slot = HeaderSlot(99)
  facts.bytes = 0
  assert uint32(retained.accumulationConsensusInfo.value.slot) == 2
  assert retained.accumulationConsensusInfo.value.bytes > 0
  let detached = retained.accumulationConsensusState.value
  retained = default(PreparedAccumulationConsensus)
  assert detached.lookup(chapterKey(StateChapter(11))).value.bytes == fixedSlot(2)
  cycle(source)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(source) # Genuine earlier authority stays fixed; every newly derived owner is scoped.
  let after = getOccupiedMem()
  assert before == after, "consensus composition ARC release"
  recordArcRelease("accumulation_consensus", 1000, before, after)
  echo "Accumulation consensus composition passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fallible report I/O remains a strict failed native execution.
except:
  quit(2)
