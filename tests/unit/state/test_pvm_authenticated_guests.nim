# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_authenticated_guests_arc_release"}

## Genuine signed rounds bind current guest coverage to admitted state, posterior entropy and profile.
import std/[assertions, envvars, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, header]
import ../../../src/codec/work/digest as work_digest
import ../../../src/codec/[assurances, report_owned]
import ../../../src/codec/state/[safrole as state_safrole, layout as state_layout,
    privileges as state_privileges, workqueues as state_workqueues]
import ../../../src/codec/c2_records
import "../../../src/state/accumulation/block/guests" as accumulation_block_guests
import ../../../src/state/accumulation/[guest_runner as accumulation_guest_runner,
    coverage as accumulation_coverage, annulment as accumulation_annulment,
    outcome as accumulation_outcome, effects as accumulation_effects,
    context as accumulation_context, invocation as accumulation_invocation,
    inputs as accumulation_inputs, round as accumulation_round, queue as accumulation_queue,
    operands as accumulation_operands, service as accumulation_service, skip as accumulation_skip,
    absent as accumulation_absent]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/store
import ../../support/[accumulation_runner_context, accumulation_execution_context,
  report_admission_context, accumulation_current_guests_context, arc_evidence]
proc parity(fixture: ExecutionFixture): BlockAccumulationGuests =
  ## A separately composed explicit run is an oracle for provider rows; only the block adapter supplies authority.
  let before = fixture.state.snapshot.value
  let executed = runBlockAccumulationGuests(fixture.round, runnerParameters(), currentGuestLimits())
  assert executed.error == BlockGuestError.None, $executed.error
  let coverage = executed.value.guestCoverage.value
  let stage = fixture.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let entropy = decodeStateEntropy(stage.snapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  let inputs = fixture.round.roundProjection.value.roundInputs.value
  let manual = runAccumulationGuests(inputs, stage.admitted.admittedState, slot, entropy,
    runnerParameters(), currentGuestLimits()).value
  let info = coverage.coverageInfo.value
  assert info.services == manual.coverageInfo.value.services and uint32(info.slot) == uint32(slot)
  assert uint64(info.gasUsed) == uint64(manual.coverageInfo.value.gasUsed)
  assert sameAccumulationInputs(executed.value.guestRound.value.roundProjection.value.roundInputs.value, inputs)
  assert sameStateSnapshot(coverage.coverageAnnulment.value.annulmentPrior.value, before)
  for index in 0..<info.services:
    let ordinal = AccumulationCoverageIndex(uint64(index))
    let row = coverage.coverageRowAt(ordinal).value
    let expected = manual.coverageRowAt(ordinal).value
    assert uint32(row.service) == uint32(expected.service) and row.kind == expected.kind
    assert uint64(row.gasUsed) == uint64(expected.gasUsed)
    if row.kind == AccumulationCoverageKind.Executed:
      let invocation = coverage.coverageOriginalAt(
          ordinal).value.outcomeContext.value.effectInitialContext.value.contextInvocation.value.bootstrapInfo.value
      assert array[32, byte](invocation.entropy) == array[32, byte](entropy)
      assert uint32(invocation.slot) == uint32(slot) # Every actual bootstrap uses posterior authority.
  assert sameStateSnapshot(fixture.state.snapshot.value, before)
  executed.value
proc absentCase(base: OwnedReport): BlockAccumulationGuests =
  ## A real unknown always-service cannot become a service lookup failure or a synthetic unavailable-code skip.
  var options = signedBlockFixtureConfig()
  options.withAvailable = true
  let entry = privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](2),
    always: @[AlwaysAccumulate(service: ServiceIndex(123), gas: PrivilegeGas(300000))]),
    executionRoundConfig().privileges).value
  options.extra = @[entry]
  let context = authored(base, options)
  let admitted = planBlockReports(context.staged, context.older, config()).value
  let queue = planBlockAccumulationQueue(admitted, executionQueueConfig()).value
  let round = planBlockInitialAccumulation(queue, executionRoundConfig()).value
  let executed = runBlockAccumulationGuests(round, runnerParameters(), currentGuestLimits())
  assert executed.error == BlockGuestError.None, $executed.error
  let coverage = executed.value.guestCoverage.value
  let info = coverage.coverageInfo.value
  assert info.services == 1 and info.absent == 1 and uint64(info.gasUsed) == 0
  let missing = coverage.coverageAbsentAt(AccumulationCoverageIndex(0)).value
  assert uint32(missing.absentInfo.value.service) == 123
  assert sameStateSnapshot(missing.absentState.value, context.original.snapshot.value)
  executed.value
proc main() {.raises.} =
  ## Prepared reports still pass production signatures/admission; local limits never replace protocol validity.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact transport bytes.
  let base = decodeOwnedReport(wire, 2).value
  let fixture = executionFixture(base)
  let retained = parity(fixture)
  for ending in [ExecutionEnding.Panic, ExecutionEnding.Exhausted, ExecutionEnding.HostExhausted,
      ExecutionEnding.Missing]:
    var options = executionFixtureConfig()
    options.first = ending
    options.second = ExecutionEnding.Missing
    discard parity(executionFixture(base, options)) # Actual terminal alternatives retain original gas.
  let absent = absentCase(base)
  var options = executionFixtureConfig()
  options.empty = true
  let empty = executionFixture(base, options)
  discard parity(empty)
  let refused = runBlockAccumulationGuests(default(BlockAccumulationRound), runnerParameters(),
      currentGuestLimits())
  assert refused.error == BlockGuestError.InvalidRound
  for parameters in [default(Parameters), runnerParameters(cores = 3), runnerParameters(epoch = 13),
      runnerParameters(queue = 79)]:
    for round in [fixture.round, empty.round]:
      assert runBlockAccumulationGuests(round, parameters, currentGuestLimits()).error ==
          BlockGuestError.InvalidParameters
  var limits = currentGuestLimits()
  limits.contexts.validators = ValidatorCount(9)
  assert runBlockAccumulationGuests(empty.round, runnerParameters(), limits).error ==
      BlockGuestError.InvalidParameters
  limits = currentGuestLimits()
  limits.coverage.gas = Gas(0)
  let gasFailure = runBlockAccumulationGuests(fixture.round, runnerParameters(), limits)
  assert gasFailure.error == BlockGuestError.GuestFailure
  assert gasFailure.guestFailure.error == AccumulationGuestError.CoverageFailure
  assert gasFailure.guestFailure.coverageFailure == AccumulationCoverageError.GasExceeded
  limits = currentGuestLimits()
  limits.services = ElementLimit(1)
  let bounded = runBlockAccumulationGuests(fixture.round, runnerParameters(), limits)
  assert bounded.error == BlockGuestError.GuestFailure
  assert bounded.guestFailure.error == AccumulationGuestError.LimitExceeded
  assert default(BlockAccumulationGuests).guestRound.error == BlockGuestError.Uninitialized
  assert default(BlockAccumulationGuests).guestCoverage.error == BlockGuestError.Uninitialized
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = runBlockAccumulationGuests(retained.guestRound.value, runnerParameters(),
        currentGuestLimits()).value
    assert local.guestCoverage.value.coverageInfo.value.services == 2
    let missing = runBlockAccumulationGuests(absent.guestRound.value, runnerParameters(),
        currentGuestLimits()).value
    assert missing.guestCoverage.value.coverageInfo.value.absent ==
        1 # Genuine source owners release across both execution branches.
  let after = getOccupiedMem()
  assert before == after, "authenticated current guests release"
  recordArcRelease("pvm_authenticated_guests", 1000, before, after)
  echo "PVM authenticated guests passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected setup failures remain suite failures.
except:
  quit(2)
