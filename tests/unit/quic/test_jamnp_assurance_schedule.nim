# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_assurance_schedule_arc_release"}

## Independent absolute timing edges and genuine pending work distinguish parent C8 assurers from current/pending-C4 authors without granting possession or private signing authority.
import std/[assertions, syncio, monotimes, times, posix/posix]
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, work_submission]
import ../../../src/rpc/server
import ../../../src/jamnp-s/[assurance_schedule, assurance_duty, assurance_record, topology]
import ../../../src/chain/[genesis, parameters]
import ../../../src/codec/[bounded, header, assurances]
import ../../../src/codec/state/[safrole, consensus, layout, trie]
import ../../../src/state/store
import ../../support/[jamnp_assurance_fixture, jamnp_topology_fixture, current_application_context, arc_evidence]
proc processId(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## The public OS ABI gives this process a distinct test-owned chain-file path without package globals.
proc limits(source: BlockSnapshotResult): AssuranceScheduleLimits =
  ## Independent chapter, full duty, topology and all-three-roster output reservations are explicit.
  AssuranceScheduleLimits(duty: AssuranceDutyLimits(chapterBytes: ByteLimit(1000000),
    readBytes: ByteLimit(4000000), reports: ElementLimit(341), requests: ElementLimit(341*1023)),
    topology: topologyLimits(3, int(uint64(source.value.epochSlots))), plannedBytes: ByteLimit(1000000))
proc changedStaging(source: BlockSnapshotResult): BlockSnapshotResult =
  ## Explicitly structural same-header/different-map data poisons C7; it does not claim a GP-valid transition or admitted block.
  let saved = source.value
  var entries: seq[StateEntry] = @[]
  let staging = chapterKey(StateChapter(7))
  for index in 0..<saved.keyCount:
    # All other complete state values retain their original bytes; only irrelevant staging changes.
    let key = saved.keyAt(StateKeyIndex(index))
    if array[31, byte](key) != array[31, byte](staging):
      entries.add(StateEntry(key: key, value: saved.lookup(key).value.bytes))
  entries.add(StateEntry(key: staging, value: @[255'u8]))
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert saved.header.encodeOwnedHeader(wire).error == HeaderError.None, "unchanged structural header"
  captureBlockSnapshot(wire, entries, saved.chainParameters)
proc timing() =
  ## Literal six-second slots have preparation at2, distribution at4 and expiry at6; epoch-boundary deadlines remain in absolute Common Era seconds.
  assert assuranceWindow(AssuranceTime(0), 6).error == AssuranceScheduleError.Unavailable
  assert assuranceWindow(AssuranceTime(1), 6).error == AssuranceScheduleError.Unavailable
  for clock in 2'u64..5'u64:
    let window = assuranceWindow(AssuranceTime(clock), 6).value
    assert uint32(window.targetSlot) == 1 and uint64(window.prepareAt) == 2 and
      uint64(window.sendAt) == 4 and uint64(window.closeAt) == 6, "literal upcoming-slot timing"
  assert assuranceWindow(AssuranceTime(6), 6).error == AssuranceScheduleError.Unavailable,
    "expired slot cannot revive its preparation window"
  let beforeEpoch = assuranceWindow(AssuranceTime(68), 6).value
  let afterEpoch = assuranceWindow(AssuranceTime(74), 6).value
  assert uint32(beforeEpoch.targetSlot) == 12 and uint64(beforeEpoch.sendAt) == 70,
    "possible authors switch two seconds before the72-second epoch"
  assert uint32(afterEpoch.targetSlot) == 13 and uint64(afterEpoch.sendAt) == 76,
    "first new-epoch assurance distribution four seconds after epoch"
  assert assuranceWindow(AssuranceTime(2), 0).error == AssuranceScheduleError.InvalidPolicy
  assert assuranceWindow(AssuranceTime(high(uint64)), 6).error ==
      AssuranceScheduleError.InvalidTime,
    "unrepresentable E4 slot never wraps into a valid opportunity"
proc genuine(fixture: AssuranceAcquisitionFixture) =
  ## Actual complete-parent C8/C10 data selects requested cores; existing topology independently supplies C4 future authors.
  let source = fixture.source
  let policy = limits(source)
  let period = source.value.chainParameters.get(slotPeriodSec)
  let epoch = uint64(source.value.epochSlots)
  assert period >= 3 and epoch > 1, "genuine profile timing control: " & $period & " / " & $epoch
  let slot = uint64(source.value.slot)
  let earliest = slot div epoch*epoch+(6+period-1) div period
  let target = max(slot+1, earliest)
  let window = assuranceWindow(AssuranceTime(target*period-min(4'u64, period)), period).value
  let captured = captureAssuranceSchedule(source, fixture.local, window, policy)
  assert captured.error == AssuranceScheduleError.None, "genuine timed source qualification: " &
      $captured.error
  let plan = captured.value
  let info = plan.scheduleInfo.value
  let topology = captureValidatorTopology(source, policy.topology).value
  let expected = if target div epoch == slot div epoch: ValidatorEpoch.Current else: ValidatorEpoch.Next
  assert info.authorEpoch == expected and info.authors == topology.population(expected),
    "target-slot author epoch is independent of current assurer set"
  for ordinal in 0..<info.authors:
    assert array[32, byte](plan.scheduleTarget(ordinal).value.identity) == array[32, byte](
      topology.membershipAt(expected, StateValidatorIndex(uint64(ordinal))).value.identity),
      "exact original author routing order"
  assert plan.scheduleTarget(-1).error == AssuranceScheduleError.InvalidIndex and
    plan.scheduleTarget(info.authors).error == AssuranceScheduleError.InvalidIndex
  assert plan.matches(source) and not plan.matches(unavailableGenesis()), "complete parent binding"
  let bits = plan.scheduleSelection.value
  assert (bits.bytes[0] and 1) != 0, "genuine retained source's core-zero pending assignment requested"
  var selected = 0
  for core in 0..<344:
    # The known original core is positive; exact source counts and clear unused suffix bits reject fabricated pending-core claims.
    let marked = (bits.bytes[core div 8] and byte(1 shl (core mod 8))) != 0
    if marked:
      assert core < int(uint64(info.duty.cores)), "no non-profile core requested"
      inc selected
  assert selected == info.duty.assignments, "all and only actual pending core positions requested"
  let boundary = (slot div epoch+1)*epoch
  let crossing = assuranceWindow(AssuranceTime(boundary*period-min(4'u64, period)), period).value
  let future = captureAssuranceSchedule(source, fixture.local, crossing, policy)
  assert future.error == AssuranceScheduleError.None and
    future.value.scheduleInfo.value.authorEpoch == ValidatorEpoch.Next and
    future.value.scheduleInfo.value.authors == topology.population(ValidatorEpoch.Next),
    "old parent C8 assures while next pending-C4 authors are selected"
  let changed = changedStaging(source)
  assert changed.error == GenesisError.None and not plan.matches(changed),
    "same header with a different complete map revokes the old plan"
  assert captureAssuranceSchedule(changed, fixture.local, crossing, policy).error ==
    AssuranceScheduleError.None, "C7 staging never substitutes for pending C4 authors"
  let firstNewTarget = boundary+(6+period-1) div period
  let firstNew = assuranceWindow(AssuranceTime(firstNewTarget*period-min(4'u64, period)), period).value
  assert captureAssuranceSchedule(source, fixture.local, firstNew, policy).error ==
    AssuranceScheduleError.InvalidTime, "old C8 cannot masquerade as first new-epoch assurer set"
  var malformed = window
  malformed.closeAt = AssuranceTime(uint64(window.closeAt)+1)
  assert captureAssuranceSchedule(source, fixture.local, malformed, policy).error ==
    AssuranceScheduleError.InvalidTime, "caller-provided timing metadata is revalidated"
  var exact = policy
  exact.plannedBytes = ByteLimit(4096+9*3*128)
  assert captureAssuranceSchedule(source, fixture.local, window, exact).error ==
      AssuranceScheduleError.None,
    "whole source-free roster reservation"
  exact.plannedBytes = ByteLimit(uint64(exact.plannedBytes)-1)
  assert captureAssuranceSchedule(source, fixture.local, window, exact).error ==
      AssuranceScheduleError.LimitExceeded,
    "minus-one output refuses before topology publication"
proc opportunity(fixture: AssuranceAcquisitionFixture): AssuranceWindow =
  ## Synthetic fixture parameters use their actual configured period, independently of the normative six-second edge witnesses.
  let period = fixture.source.value.chainParameters.get(slotPeriodSec)
  let slot = uint64(fixture.source.value.slot)
  let epoch = uint64(fixture.source.value.epochSlots)
  let target = max(slot+1, slot div epoch*epoch+(6+period-1) div period)
  assuranceWindow(AssuranceTime(target*period-min(4'u64, period)), period).value
proc waitDone(worker: var StateProofWorker) =
  ## Only synchronized worker phase is sampled while native execution owns the complete source aliases.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded native schedule completion"
proc waitDone(owner: var Services) =
  ## Host callers inspect no canonical map through an outstanding or completed lease.
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded managed schedule completion"
proc managed(fixture: AssuranceAcquisitionFixture) {.raises.} =
  ## An independently decoded trusted source exercises real Services capture/collection without an archive or private signer.
  var filename = "assurance-schedule-chain-" & $processId() & ".json"
  writeFile(filename, currentApplicationText(fixture.source.value))
  defer: discard posix.unlink(filename.toCString())
  var settings = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", filename, "--with-state",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], settings)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(settings, "managed timed assurance planning"), "independent complete source"
  let policy = limits(fixture.source)
  let window = opportunity(fixture)
  assert owner.beginAssuranceSchedule(fixture.local, default(AssuranceWindow), policy).error ==
    StateProofAdmissionError.QueryFailure and owner.stateProofAvailable, "default window retains no lease"
  let started = owner.beginAssuranceSchedule(fixture.local, window, policy)
  assert started.error == StateProofAdmissionError.None and not owner.stateProofAvailable and
    owner.rpc.chainPaused, "actual canonical/RPC planning lease"
  owner.waitDone()
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
    ProofWorkerCompletionKind.Uninitialized and not owner.stateProofAvailable,
    "foreign Done collection cannot reopen canonical access"
  let completed = owner.collectStateProof(started.value)
  assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted and
    completed.workSubmissionValue.kind == WorkJobResultKind.AssuranceScheduled,
    "closed native author/timing planning result"
  let plan = completed.workSubmissionValue.scheduledAssurance
  assert owner.assuranceScheduleCurrent(plan) and plan.matches(fixture.source), "actual full source binding"
  let cancelled = owner.beginAssuranceSchedule(fixture.local, window, policy).value
  owner.waitDone()
  assert owner.cancelStateProof(cancelled), "exact Done schedule cancellation"
  assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Cancelled,
    "cancelled plan exposes no targets or selection prefix"
  assert not owner.assuranceStorageInfo.opened and not owner.assuranceSigningConfigured,
    "planning never imports private signing or opens storage"
proc cycle(worker: var StateProofWorker, fixture: AssuranceAcquisitionFixture, index: int) =
  ## Synchronous and moved native plan graphs retire completely before each allocation comparison.
  let policy = limits(fixture.source)
  let window = opportunity(fixture)
  assert captureAssuranceSchedule(fixture.source, fixture.local, window, policy).error ==
    AssuranceScheduleError.None
  var job = captureAssuranceScheduleJob(fixture.source, fixture.local, window, policy).value
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid, "moved closed schedule input"
  worker.waitDone()
  if index mod 2 == 0: assert worker.cancel(admitted.value), "Done schedule cancellation"
  let completed = worker.collect(admitted.value)
  if index mod 2 == 0:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "cancelled native plan has no prefix"
  else:
    assert completed.kind == ProofWorkerCompletionKind.WorkSubmitted and
      completed.workSubmissionValue.kind == WorkJobResultKind.AssuranceScheduled,
      "native complete original source/role plan"
proc main() {.raises.} =
  ## Literal timing, genuine/structural keyset boundaries and actual managed lifetime precede repeated native ARC checks.
  timing()
  let fixture = assuranceAcquisitionFixture()
  genuine(fixture)
  managed(fixture)
  var worker = default(StateProofWorker)
  defer: worker.close()
  assert worker.start(), "reusable bounded scheduling worker"
  cycle(worker, fixture, 1)
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(worker, fixture, index)
  let after = getOccupiedMem()
  assert before == after, "source-free assurance scheduling ARC release"
  recordArcRelease("jamnp_assurance_schedule", 1000, before, after)
  echo "JAMNP-S assurance schedule passed"
try:
  main()
except:
  quit(2)
