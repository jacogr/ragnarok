# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed current statistics scenarios include unavailable work, original annulment and a deleted transfer recipient.
import std/assertions
import ../../src/codec/[bounded, report_owned, work_digest]
import ../../src/state/[accumulation_current_driver, accumulation_current_sequence,
  accumulation_current_statistics]
import ./[accumulation_execution_context, accumulation_current_round_context,
  accumulation_current_sequence_context, accumulation_current_driver_context, pvm_accumulation_program]

type CurrentStatisticsScenario* {.pure.} = enum ## Each case uses actual admission/guest/collapse behavior, never synthetic providers.
  Transfers, ZeroParticipants, SkippedReport, EjectedTransfer, Annulled
proc currentStatisticsLimits*(): CurrentAccumulationStatisticsLimits =
  ## Bound real history/provider work independently of the nonzero retained dictionary and gross counters.
  CurrentAccumulationStatisticsLimits(entries: ElementLimit(4), providers: ElementLimit(8),
    operands: ElementLimit(4), transfers: ElementLimit(4), services: ElementLimit(4), gas: Gas(1000000))
proc currentStatisticsCompletion*(base: OwnedReport,
    scenario: CurrentStatisticsScenario): CompletedCurrentAccumulationSequence =
  ## Construct genuine terminal coverage from signed blocks and actual current guest execution.
  var limits = currentSequenceDriverLimits()
  if scenario == CurrentStatisticsScenario.Transfers:
    let initial = currentSequenceInitialRound(base, transferGas = 100)
    return runCurrentAccumulationSequence(startCurrentAccumulationSequence(initial).value,
      limits.planning, limits.execution).value # Report plus held-transfer delivery supplies all three statistics components.
  var options = executionFixtureConfig()
  case scenario
  of CurrentStatisticsScenario.ZeroParticipants, CurrentStatisticsScenario.SkippedReport:
    options.first = ExecutionEnding.Missing
    options.second = ExecutionEnding.Missing
    options.signed.withAvailable = scenario == CurrentStatisticsScenario.SkippedReport # Only the actual selected report creates N with zero gas.
  of CurrentStatisticsScenario.EjectedTransfer:
    options.second = ExecutionEnding.Missing
    options.secondSupervisor = 42
    options.firstProgram = currentRoundServiceCode(@[
      registerImmediate(7, high(uint64)), registerImmediate(8, 99), registerImmediate(9, 0),
      registerImmediate(10, 0), registerImmediate(11, 100), registerImmediate(12, 196608), @[10'u8, 22],
      registerImmediate(7, 99), @[10'u8, 23], @[50'u8, 0]])
    limits.initial.guests.deletedAccounts = ElementLimit(
        1) # The empty junior has no code preimage/storage; ejection is real and leaves no orphan subkeys.
  of CurrentStatisticsScenario.Annulled:
    options.secondSupervisor = 42
    options.firstProgram = currentRoundServiceCode(@[registerImmediate(7, 99), registerImmediate(8,
        42), @[10'u8, 29], @[50'u8, 0]])
    options.secondProgram = currentTransferProgram(
        99) # Self transfer marks the junior; the original parent modification annuls it.
  of CurrentStatisticsScenario.Transfers:
    discard # The real three-entry path returned before constructing this one-round fixture.
  let fixture = executionFixture(base, options)
  let completed = runCurrentBlockAccumulationSequence(fixture.round, currentRoundParameters(), limits)
  assert completed.error == CurrentSequenceDriverError.None, $scenario & ":" & $completed.error
  completed.value
