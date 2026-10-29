# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed two-entry output fixtures exercise duplicate pairs and differing yields from the same service.
import std/assertions
import ../../src/codec/[bounded, report_owned]
import ../../src/codec/state/[outputs as state_outputs, workqueues as state_workqueues]
import ../../src/codec/work/digest as work_digest
import ../../src/state/accumulation/current/[outputs as accumulation_current_outputs,
    driver as accumulation_current_driver]
import ../../src/state/accumulation/round as accumulation_round
import ./[accumulation_execution_context, accumulation_current_round_context,
  accumulation_current_driver_context, report_context, pvm_accumulation_program]
proc currentOutputLimits*(): CurrentAccumulationOutputLimits =
  ## Bound three original provider visits independently of the retained unique pair capacity.
  CurrentAccumulationOutputLimits(entries: ElementLimit(3), outcomes: ElementLimit(4),
    log: OutputLogConfig(items: ElementLimit(4), maxBytes: ByteLimit(145)))
proc currentOutputCompletion*(base: OwnedReport, varied: bool,
    reportGas = 10000'u64): CompletedCurrentAccumulationSequence =
  ## Original free reservations exclude the ready report; remaining actual gas admits it in a later entry.
  var options = executionFixtureConfig()
  options.signed.ready = @[ReadyItem(report: reportFor(base, 0, [reportGas]), dependencies: @[])]
  let fixed = currentRoundServiceCode(@[registerImmediate(7, 65536), @[10'u8, 27], @[50'u8, 0]])
  options.firstProgram = if varied:
    currentRoundServiceCode(@[registerImmediate(7, 196608), registerImmediate(8, 0),
      registerImmediate(9, 32), registerImmediate(10, 14), @[10'u8, 2],
      registerImmediate(7, 196608), @[10'u8, 27], @[50'u8, 0]])
    else: fixed # Fetch14 copies empty-list versus real-operand bytes before yielding the writable page.
  options.secondProgram = fixed
  let fixture = executionFixture(base, options)
  var policy = executionRoundConfig()
  policy.blockGas = Gas(200000)
  let round = planBlockInitialAccumulation(fixture.round.roundBlockQueue.value, policy).value
  let finished = runCurrentBlockAccumulationSequence(round, currentRoundParameters(),
      currentSequenceDriverLimits())
  assert finished.error == CurrentSequenceDriverError.None, $finished.error
  let expectedEntries = if reportGas == high(uint64): 1 else: 2
  assert finished.value.completedSequenceInfo.value.entries == expectedEntries, "ready report executes later only when its original allowance fits"
  finished.value
