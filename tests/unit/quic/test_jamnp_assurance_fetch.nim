# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_assurance_fetch_arc_release"}

## Genuine canonical pending reports and explicitly structural epoch/roster variants test source-free CE137 plans, whole output admission and exact managed ownership.
import std/[assertions, syncio, monotimes, times]
import ../../../src/jamnp-s/[assurance_fetch, assurance_duty, availability_proof]
import ../../../src/app/proof/[worker, work_submission]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, assurances, guarantees, header]
import ../../../src/codec/state/[safrole, availability, layout, trie]
import ../../../src/codec/work/report
import ../../../src/state/store
import ../../../src/state/availability/specifier
import ../../support/[jamnp_assurance_fixture, jamnp_import_recovery_fixture,
    jamnp_topology_fixture, arc_evidence]
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only under bounded native completion deadlines without accessing any leased graph.
proc limits(): AssuranceFetchLimits =
  ## Independent canonical-copy and owned-output ceilings cover the complete fixture without implicit defaults.
  AssuranceFetchLimits(duty: AssuranceDutyLimits(chapterBytes: ByteLimit(1000000),
      readBytes: ByteLimit(4000000),
    reports: ElementLimit(341), requests: ElementLimit(341*1023)), plannedBytes: ByteLimit(1000000))
proc replaced(source: BlockSnapshotResult, entry: StateEntry): BlockSnapshotResult =
  ## Recommit one explicitly trusted structural chapter while preserving the exact sealed header; this does not establish GP admission.
  let saved = source.value
  var entries: seq[StateEntry] = @[]
  for index in 0..<saved.keyCount:
    # All unrelated complete chapters retain their original bytes and identity.
    let key = saved.keyAt(StateKeyIndex(index))
    if array[31, byte](key) != array[31, byte](entry.key): entries.add(StateEntry(key: key,
        value: saved.lookup(key).value.bytes))
  entries.add(entry)
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert saved.header.encodeOwnedHeader(wire).error == HeaderError.None, "exact structural header encoding"
  captureBlockSnapshot(wire, entries, saved.chainParameters)
proc atEvaluation(source: BlockSnapshotResult, slot: uint32): BlockSnapshotResult =
  ## Structural evaluation-time variants isolate roster selection; their unchanged credential bytes are not asserted to verify against the changed slot.
  let saved = source.value
  let policy = AvailabilityConfig(guarantee: GuaranteeConfig(cores: saved.cores,
      validators: ValidatorCount(1023), maxBytes: ByteLimit(1000000)),
    maxPresent: ElementLimit(341), maxBytes: ByteLimit(1000000))
  let decoded = decodeAvailabilityState(saved.lookup(chapterKey(StateChapter(10))).value.bytes,
      policy).value.snapshot
  var assignments = newSeq[AvailabilityAssignment](int(uint64(saved.cores)))
  for core in 0..<assignments.len:
    # Preserve each original core, complete report and registration while changing only its structural evaluation slot.
    let old = decoded.availabilityAt(AssignmentCoreIndex(core)).value
    if old.present:
      var guarantee = old.guarantee
      guarantee.slot = GuaranteeSlot(slot)
      assignments[core] = presentAssignment(guarantee, old.registered)
  let entry = availabilityStateEntry(assignments, policy)
  assert entry.error == AvailabilityError.None, "bounded structural C10 encoding"
  replaced(source, entry.value)
proc repeated(source: BlockSnapshotResult, local: StateEdKey): BlockSnapshotResult =
  ## The explicitly structural C8 variant preserves null gaps and three original positions of one real local key.
  let saved = source.value
  let policy = ValidatorStateConfig(cores: saved.cores, validators: ElementLimit(1023),
      maxBytes: ByteLimit(1000000))
  let decoded = decodeStateValidators(saved.lookup(chapterKey(StateChapter(8))).value.bytes,
      policy).value.value
  assert decoded.validatorCount.value == 9, "known genuine fixture population"
  var roster = newSeq[StateValidator](9)
  for index in 0..<roster.len: roster[index] = decoded.validatorAt(StateValidatorIndex(index)).value
  roster[0] = nullValidator()
  roster[2].ed25519 = local
  roster[8].ed25519 = local
  replaced(source, validatorEntry(ValidatorChapter.Active, roster, policy).value)
proc genuine(fixture: AssuranceAcquisitionFixture) =
  ## Literal original-index coordinates and independently decoded C8/C9 records check genuine C10 target provenance, not a self-rooted peer claim.
  let captured = captureAssuranceFetch(fixture.source, fixture.local, limits())
  assert captured.error == AssuranceFetchError.None, "genuine canonical fetch plan: " &
      $captured.error
  let plan = captured.value
  let info = plan.fetchInfo.value
  assert uint64(info.duty.cores) == 3 and uint64(info.duty.validators) == 9 and
      info.duty.localIndices == 1, "explicit source geometry control"
  assert plan.matches(fixture.source) and not plan.matches(unavailableGenesis()), "complete source binding"
  let duty = captureAssuranceDuty(fixture.source, fixture.local, limits().duty).value
  let policy = ValidatorStateConfig(cores: fixture.source.value.cores, validators: ElementLimit(
      1023), maxBytes: ByteLimit(1000000))
  let active = decodeStateValidators(fixture.source.value.lookup(chapterKey(StateChapter(
      8))).value.bytes, policy).value.value
  let previous = decodeStateValidators(fixture.source.value.lookup(chapterKey(StateChapter(
      9))).value.bytes, policy).value.value
  let epoch = uint64(fixture.source.value.epochSlots)
  const expected = [1'u64, 5, 0]
  for ordinal in 0..<info.duty.assignments:
    # Plan row order cannot replace the actual core or original local ordinal in the NP assignment formula.
    let core = plan.coreAt(ordinal).value
    assert uint64(core.core) < 3, "genuine source core"
    let request = plan.requestAt(ordinal, 0).value
    assert uint64(request.request.shard) == expected[int(uint64(core.core))] and uint16(
        request.validator) == 1, "literal nine-validator original coordinate"
    assert request.request.root.bytes == core.specifier.erasureRoot.bytes, "canonical full erasure root"
    let guarantee = duty.assignment(core.core).value.guarantee
    let roster = if uint64(uint32(guarantee.slot)) div epoch == uint64(uint32(
        info.duty.slot)) div epoch: active else: previous
    assert core.targets == guarantee.credentialCount, "actual non-null genuine credentials"
    for target in 0..<core.targets:
      # Independent raw-roster lookup catches wrong epoch, shuffled or compressed credential-index substitution.
      let selected = plan.targetAt(ordinal, target).value
      let index = uint16(guarantee.credentials[target].validator)
      let expectedRecord = roster.validatorAt(StateValidatorIndex(index)).value
      assert uint16(selected.validatorIndex) == index and array[32, byte](
          selected.validator.ed25519) == array[32, byte](expectedRecord.ed25519), "actual original guarantor identity"
  var exact = limits()
  exact.plannedBytes = ByteLimit(info.plannedBytes)
  assert captureAssuranceFetch(fixture.source, fixture.local, exact).error ==
      AssuranceFetchError.None, "whole output exact limit"
  exact.plannedBytes = ByteLimit(info.plannedBytes-1)
  assert captureAssuranceFetch(fixture.source, fixture.local, exact).error ==
      AssuranceFetchError.LimitExceeded, "one-byte output deficit refuses entire plan"
  assert plan.requestAt(-1, 0).error == AssuranceFetchError.InvalidIndex and plan.requestAt(0,
      1).error == AssuranceFetchError.InvalidIndex, "no invalid request extraction"
  assert plan.targetAt(0, 3).error == AssuranceFetchError.InvalidIndex, "no target-array suffix extraction"
  let changed = repeated(fixture.source, fixture.local)
  assert changed.error == GenesisError.None and not plan.matches(changed), "same header with changed full map revokes old plan"
  let many = captureAssuranceFetch(changed, fixture.local, limits())
  assert many.error == AssuranceFetchError.None and many.value.fetchInfo.value.duty.localIndices ==
      3, "all original repeated local positions"
  assert many.value.fetchInfo.value.plannedBytes == info.plannedBytes+32, "output grows by local-index storage rather than allocating the request product"
  const originals = [1'u16, 2, 8]
  const coordinates = [[1'u64, 2, 8], [5'u64, 6, 3], [0'u64, 1, 7]]
  for row in 0..<info.duty.assignments:
    # Repeated keys keep every original index, including the final position after a null predecessor.
    let core = int(uint64(many.value.coreAt(row).value.core))
    for local in 0..<3:
      let selected = many.value.requestAt(row, local).value
      assert uint16(selected.validator) == originals[local] and uint64(selected.request.shard) ==
          coordinates[core][local], "literal repeated-key coordinates"
proc epochs(fixture: AssuranceAcquisitionFixture): BlockSnapshotResult =
  ## Explicit independently trusted structural maps distinguish original current/prior epoch keys and unknown history without claiming new GP credential validity.
  let source = registrationSnapshot(fixture.availability, slot = 40, active = 9, previous = 12,
      registered = 40, highCredentials = false)
  assert source.error == GenesisError.None, "complete structural epoch source"
  let current = captureAssuranceFetch(source, topologyKey(61), limits())
  assert current.error == AssuranceFetchError.None, "current epoch target plan"
  assert array[32, byte](current.value.targetAt(0, 0).value.validator.ed25519) == array[32, byte](
      topologyKey(60)), "current credential selects original C8 index zero"
  let priorSource = atEvaluation(source, 35)
  let prior = captureAssuranceFetch(priorSource, topologyKey(61), limits())
  assert prior.error == AssuranceFetchError.None, "prior epoch target plan"
  assert array[32, byte](prior.value.targetAt(0, 0).value.validator.ed25519) == array[32, byte](
      topologyKey(20)), "prior credential selects C9 index zero rather than current C8"
  let high = registrationSnapshot(fixture.availability, slot = 40, active = 9, previous = 12,
      registered = 40, highCredentials = true)
  let wrongPopulation = captureAssuranceFetch(high, topologyKey(61), limits())
  assert wrongPopulation.error == AssuranceFetchError.TargetFailure and
      wrongPopulation.targetError.error == AssuranceDutyError.InvalidState, "current epoch cannot borrow an out-of-range index from the larger prior roster"
  let highPrior = captureAssuranceFetch(atEvaluation(high, 35), topologyKey(61), limits())
  assert highPrior.error == AssuranceFetchError.None and uint16(highPrior.value.targetAt(0,
      0).value.validatorIndex) == 10, "previous epoch retains its independent larger population"
  assert array[32, byte](highPrior.value.targetAt(0, 0).value.validator.ed25519) == array[32, byte](
      topologyKey(30)), "original C9 tail position is not shuffled or compressed"
  let rosterPolicy = ValidatorStateConfig(cores: source.value.cores, validators: ElementLimit(1023),
      maxBytes: ByteLimit(1000000))
  var records = topologyRecords(1, 9)
  records[0] = nullValidator()
  let missingTarget = replaced(source, validatorEntry(ValidatorChapter.Active, records,
      rosterPolicy).value)
  let skipped = captureAssuranceFetch(missingTarget, topologyKey(61), limits())
  assert skipped.error == AssuranceFetchError.None and skipped.value.coreAt(0).value.targets == 1, "null original credential is unavailable rather than a dial identity"
  assert uint16(skipped.value.targetAt(0, 0).value.validatorIndex) == 1, "skipping null targets never renumbers the surviving original credential"
  records[0] = records[1]
  var firstMetadata = array[128, byte](records[0].metadata)
  var secondMetadata = array[128, byte](records[1].metadata)
  firstMetadata[30] = 1
  secondMetadata[30] = 2
  records[0].metadata = StateValidatorMetadata(firstMetadata)
  records[1].metadata = StateValidatorMetadata(secondMetadata)
  let repeatedTargets = captureAssuranceFetch(replaced(source, validatorEntry(
      ValidatorChapter.Active, records, rosterPolicy).value), topologyKey(61), limits())
  assert repeatedTargets.error == AssuranceFetchError.None and repeatedTargets.value.coreAt(
      0).value.targets == 2, "repeated actual keys retain distinct original routing records"
  assert array[128, byte](repeatedTargets.value.targetAt(0, 0).value.validator.metadata)[30] ==
      1 and array[128, byte](repeatedTargets.value.targetAt(0, 1).value.validator.metadata)[30] ==
      2, "complete original routing metadata survives"
  var detached = repeatedTargets.value.targetAt(0, 0).value
  detached.validator.ed25519 = default(StateEdKey)
  assert array[32, byte](repeatedTargets.value.targetAt(0, 0).value.validator.ed25519) == array[32,
      byte](topologyKey(61)), "returned fixed target copies cannot mutate the private plan"
  let unknown = atEvaluation(source, 11)
  let refused = captureAssuranceFetch(unknown, topologyKey(61), limits())
  assert refused.error == AssuranceFetchError.TargetFailure and refused.targetError.error ==
      AssuranceDutyError.UncertainEpoch, "older unavailable keysets cannot be invented"
  let future = captureAssuranceFetch(atEvaluation(source, 41), topologyKey(61), limits())
  assert future.error == AssuranceFetchError.DutyFailure, "future evaluation refuses canonical qualification"
  unknown
proc staged(source: BlockSnapshotResult, local: StateEdKey): WorkSubmissionJob =
  ## Retire the capture wrapper and source aliases before moved publication to the native worker.
  let captured = captureAssurancePlanning(source, local, limits())
  assert captured.error == WorkJobError.None, "bounded closed planning capture"
  captured.value
proc cycle(worker: var StateProofWorker, source: BlockSnapshotResult, local: StateEdKey, index: int,
    failure = false) =
  ## The exact generation retains source capacity through Done and completed cancellation; no partially planned prefix escapes.
  var job = staged(source, local)
  let started = worker.submit(job)
  assert started.error == ProofWorkerError.None and not job.valid, "moved native planning job"
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded native planning completion"
    discard pauseMicros(100)
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized, "foreign planning ticket cannot retire source"
  if index mod 2 == 0: assert worker.cancel(started.value), "exact Done planning cancellation"
  let completed = worker.collect(started.value)
  if index mod 2 == 0:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "cancelled plan is withheld"
  else:
    assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted, "actual planning completion"
    let outcome = completed.workSubmissionValue
    if failure:
      assert outcome.kind == WorkJobResultKind.AssurancePlanningFailure and
          outcome.assurancePlanningError.error == AssuranceFetchError.TargetFailure, "actual late target refusal exposes no plan prefix"
    else:
      assert outcome.kind == WorkJobResultKind.AssurancePlanned and
          outcome.plannedAssurance.matches(source), "source-free native plan after exact collection"
  assert not worker.active(started.value), "stale planning generation cannot revive"
proc main() {.raises.} =
  ## Genuine report execution precedes source-qualified plans; structural epoch cases remain labelled and managed lifetime has fresh ARC evidence.
  assert not default(AssuranceFetchPlan).valid and default(AssuranceFetchPlan).fetchInfo.error ==
      AssuranceFetchError.Uninitialized, "default plan has no authority"
  let fixture = assuranceAcquisitionFixture()
  genuine(fixture)
  let unknown = epochs(fixture)
  var worker = default(StateProofWorker)
  defer: worker.close()
  assert worker.start(), "reusable planning worker"
  cycle(worker, fixture.source, fixture.local, 1)
  cycle(worker, unknown, topologyKey(61), 3, failure = true)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Every successful/cancelled job retires canonical roster owners and private source-free plan storage before the next turn.
    if index mod 3 == 0: cycle(worker, unknown, topologyKey(61), index, failure = true)
    else: cycle(worker, fixture.source, fixture.local, index)
  let after = getOccupiedMem()
  assert before == after, "assurance fetch plan ARC release"
  recordArcRelease("jamnp_assurance_fetch", 1000, before, after)
  echo "JAMNP-S assurance fetch plans passed"
try:
  main()
except:
  quit(2)
