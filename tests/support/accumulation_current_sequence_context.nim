# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed current sequence fixture excludes an available report initially and holds a supervised transfer for later execution.
import std/assertions
import ../../src/codec/[bounded, composite, report_owned]
import ../../src/codec/work/digest as work_digest
import ../../src/state/accumulation/current/[sequence as accumulation_current_sequence,
    round as accumulation_current_round]
import ../../src/state/accumulation/[round as accumulation_round,
    transfer_partition as accumulation_transfer_partition]
import ./[accumulation_execution_context, accumulation_current_round_context]
proc currentContinuationLimits*(): CurrentContinuationLimits =
  ## Small finite ceilings include the affordable report, its digest and one held transfer classification.
  let base = executionRoundConfig()
  CurrentContinuationLimits(reports: ElementLimit(2), digests: ElementLimit(4),
      operands: base.operands,
    inputs: base.inputs, partition: TransferPartitionLimits(transfers: ElementLimit(2),
        services: ElementLimit(2), checks: ElementLimit(64)))
proc currentSequenceInitialRound*(base: OwnedReport,
    empty = false, transferGas = 3'u64): PreparedCurrentAccumulationRound =
  ## Initial free allowances exhaust declared200000 gas; actual guests leave room for the previously available report.
  var options = executionFixtureConfig()
  options.signed.withAvailable = true
  options.empty = empty
  if not empty:
    options.firstProgram = currentTransferProgram(99, transferGas)
    options.secondSupervisor = 42 # The next active report42 prevents concurrent incoming junior credit.
  let fixture = executionFixture(base, options)
  var config = executionRoundConfig()
  config.blockGas = Gas(if empty: 0 else: 200000)
  let round = planBlockInitialAccumulation(fixture.round.roundBlockQueue.value, config).value
  assert uint64(round.roundProjection.value.roundInfo.value.prefix) == 0, "initial report excluded by declared allowance reservation"
  let completed = runCurrentBlockAccumulationRound(round, currentRoundParameters(),
      currentRoundLimits())
  assert completed.error == CurrentAccumulationRoundError.None, $completed.error
  completed.value
