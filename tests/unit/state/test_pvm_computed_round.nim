# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_round_arc_release"}

## Original computed gas and exact parent privileges bind real initial accumulation inputs without guest execution.

import std/assertions
import std/syncio
import ../../../src/state/computed_round as state_computed_round
import ../../../src/state/computed_publication as state_computed_publication
import ../../../src/state/computed_admission as state_computed_admission
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/state_layout as codec_state_layout
import ../../support/pvm_computed_round
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reject unexpected hashing after the real computed/signed source pipeline finishes.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Inspect actual backend activity without substituting successful results.
proc expect[T](outcome: ComputedRoundResult[T], reason: ComputedRoundError) =
  ## Check exact refusal alternative before extracting application data or selected child reasons.
  assert outcome.error == reason, "computed round reason"
let source = roundFixture()
let config = computedRoundConfig(source)
let done = prepareComputedRound(source, config).value
let plan = done.computedRoundPlan.value
let projection = plan.roundProjection.value
let info = projection.roundInfo.value
assert uint64(info.budget) == 1000000 and uint64(info.allowanceGas) == 0
assert uint64(info.reportGas) == 100 and uint64(info.prefix) == 1 and info.dispatch
let originalParameters = done.computedRoundParameters.value
assert originalParameters.get(maxAccumulateGas) == 100000 and originalParameters.get(
    blockGasLimit) == 1000000
let privileges = privilegeInfo(projection.roundPrivileges.value).value
assert privileges.cores == 3 and uint32(privileges.manager) == 42 and privileges.always == 0
for index in 0..<3:
  assert uint32(privilegeAssignerAt(projection.roundPrivileges.value, PrivilegeCoreIndex(uint64(
      index))).value) == 42 # Read the canonical original assigner list.
let inputs = projection.roundInputs.value
assert inputs.invocationServiceCount.value == 1
let service = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
assert uint32(service.service) == 42
let parent = source.computedSuccessorSource.value.computedAdmissionReports.value.reportBlockStage.value.value.admitted.admittedState
assert sameStateSnapshot(plan.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState, parent)
let emptySource = roundFixture(withReady = false)
let empty = prepareComputedRound(emptySource, computedRoundConfig(
    emptySource)).value.computedRoundPlan.value.roundProjection.value
assert not empty.roundInfo.value.dispatch and uint64(empty.roundInfo.value.prefix) == 0
assert empty.roundInputs.value.invocationServiceCount.value == 0
let missingState = roundFixture(withRound = false)
let missing = prepareComputedRound(missingState, computedRoundConfig(missingState))
expect(missing, ComputedRoundError.RoundFailure)
assert missing.roundError == AccumulationRoundError.MissingState
expect(prepareComputedRound(default(ComputedReportSuccessor), config),
    ComputedRoundError.InvalidSource)
for variant in 0..<2:
  var wrong = config
  if variant == 0: wrong.round.reportGas = Gas(1) # Report gas cannot replace original execution parameters.
  else: wrong.round.blockGas = Gas(1) # Neither can the block-wide gas parameter.
  reset(1)
  expect(prepareComputedRound(source, wrong), ComputedRoundError.ProfileMismatch)
  assert hashes() == 0
  reset(0)
var short = config
short.queue.items = ElementLimit(0)
let queueFailure = prepareComputedRound(source, short)
expect(queueFailure, ComputedRoundError.QueueFailure)
assert queueFailure.queueError == AccumulationQueueError.LimitExceeded
short = config
short.round.privileges.maxBytes = ByteLimit(0)
let roundFailure = prepareComputedRound(source, short)
expect(roundFailure, ComputedRoundError.RoundFailure)
assert roundFailure.roundError == AccumulationRoundError.LimitExceeded
reset(1)
expect(prepareComputedRound(source, config), ComputedRoundError.None)
assert hashes() == 0, "initial round planning performs no hashes"
reset(0)
expect(default(ComputedAccumulationRound).computedRoundSource, ComputedRoundError.Uninitialized)
expect(default(ComputedAccumulationRound).computedRoundPlan, ComputedRoundError.Uninitialized)
expect(default(ComputedAccumulationRound).computedRoundParameters, ComputedRoundError.Uninitialized)
proc detached(): ComputedAccumulationRound =
  ## Retain actual source, original parameters, privilege snapshot and service inputs after caller owners retire.
  let source = roundFixture()
  prepareComputedRound(source, computedRoundConfig(source)).value
let retained = detached()
assert retained.computedRoundPlan.value.roundProjection.value.roundInputs.value.invocationServiceCount.value == 1
proc cycle(source: ComputedReportSuccessor, config: ComputedRoundConfig) =
  ## Release complete queue/privilege/operand/service preparation and copied original parameters each iteration.
  let round = prepareComputedRound(source, config).value
  discard round.computedRoundSource.value
  discard round.computedRoundParameters.value
  discard round.computedRoundPlan.value.roundProjection.value.roundInputs.value
cycle(source, config)
let before = getOccupiedMem()
for i in 0..<1000: cycle(source, config) # No completed preparation history remains retained.
let after = getOccupiedMem()
assert before == after, "computed round ARC release"
recordArcRelease("pvm_computed_round", 1000, before, after)
echo "PVM computed round passed"
echo "ARC_RELEASE cycles=1000 unchanged"
