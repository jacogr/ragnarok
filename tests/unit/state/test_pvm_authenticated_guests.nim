# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_authenticated_guests_arc_release"}

## Genuine signed rounds bind current guest coverage to admitted state, posterior entropy and profile.
import std/[assertions, envvars, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, header, work_digest, assurances, report_owned,
  state_safrole, state_layout,
  state_privileges, state_workqueues, c2_records]
import ../../../src/state/[accumulation_block_guests, accumulation_guest_runner,
  accumulation_coverage, accumulation_annulment, accumulation_outcome, accumulation_effects,
  accumulation_context,
  accumulation_invocation, accumulation_inputs, accumulation_round, accumulation_queue,
  accumulation_operands, accumulation_service, accumulation_skip, accumulation_absent,
  report_admission, block_transition, block_admission, store]
import ../../support/[accumulation_runner_context, accumulation_execution_context,
  report_admission_context, arc_evidence]
proc policy(): AccumulationGuestLimits =
  ## Reuse maintained tiny-chain engine ceilings while explicitly enabling current proof capture.
  let old = runnerLimits()
  AccumulationGuestLimits(services: ElementLimit(2), preimageBytes: old.preimageBytes,
    probes: old.probes, initialization: old.initialization, contexts: old.contexts,
    fetch: old.fetch, copyBytes: old.copyBytes, steps: old.steps, calls: old.calls,
    cycles: old.cycles, provisions: old.provisions, modifiedAccounts: ElementLimit(4),
    accountWriteFacts: ElementLimit(4), createdAccounts: ElementLimit(2),
    annulment: AccumulationAnnulmentLimits(outcomes: ElementLimit(2), modified: ElementLimit(8),
      checks: ElementLimit(128)),
    coverage: AccumulationCoverageLimits(services: ElementLimit(2), executed: ElementLimit(2),
      skipped: ElementLimit(2), absent: ElementLimit(2), checks: ElementLimit(128), gas: Gas(high(uint64))))
proc parity(fixture: ExecutionFixture): BlockAccumulationGuests =
  ## A separately composed explicit run is an oracle for provider rows; only the block adapter supplies authority.
  let before = fixture.state.snapshot.value
  let executed = runBlockAccumulationGuests(fixture.round, runnerParameters(), policy())
  assert executed.error == BlockGuestError.None, $executed.error
  let coverage = executed.value.guestCoverage.value
  let stage = fixture.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let entropy = decodeStateEntropy(stage.snapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  let inputs = fixture.round.roundProjection.value.roundInputs.value
  let manual = runAccumulationGuests(inputs, stage.admitted.admittedState, slot, entropy,
    runnerParameters(), policy()).value
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
  let executed = runBlockAccumulationGuests(round, runnerParameters(), policy())
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
      policy())
  assert refused.error == BlockGuestError.InvalidRound
  for parameters in [default(Parameters), runnerParameters(cores = 3), runnerParameters(epoch = 13),
      runnerParameters(queue = 79)]:
    for round in [fixture.round, empty.round]:
      assert runBlockAccumulationGuests(round, parameters, policy()).error ==
          BlockGuestError.InvalidParameters
  var limits = policy()
  limits.contexts.validators = ValidatorCount(9)
  assert runBlockAccumulationGuests(empty.round, runnerParameters(), limits).error ==
      BlockGuestError.InvalidParameters
  limits = policy()
  limits.coverage.gas = Gas(0)
  let gasFailure = runBlockAccumulationGuests(fixture.round, runnerParameters(), limits)
  assert gasFailure.error == BlockGuestError.GuestFailure
  assert gasFailure.guestFailure.error == AccumulationGuestError.CoverageFailure
  assert gasFailure.guestFailure.coverageFailure == AccumulationCoverageError.GasExceeded
  limits = policy()
  limits.services = ElementLimit(1)
  let bounded = runBlockAccumulationGuests(fixture.round, runnerParameters(), limits)
  assert bounded.error == BlockGuestError.GuestFailure
  assert bounded.guestFailure.error == AccumulationGuestError.LimitExceeded
  assert default(BlockAccumulationGuests).guestRound.error == BlockGuestError.Uninitialized
  assert default(BlockAccumulationGuests).guestCoverage.error == BlockGuestError.Uninitialized
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = runBlockAccumulationGuests(retained.guestRound.value, runnerParameters(), policy()).value
    assert local.guestCoverage.value.coverageInfo.value.services == 2
    let missing = runBlockAccumulationGuests(absent.guestRound.value, runnerParameters(), policy()).value
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
