# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_accumulation_statistics_arc_release"}

## Current terminal providers prove S(s) counts across real execution, unavailable work, annulment and deleted recipients.
import std/[assertions, envvars, syncio]
import ../../../src/codec/bounded
import ../../../src/codec/work/digest as work_digest
import ../../../src/codec/report_owned
import ../../../src/codec/state/[statistics as state_statistics, layout as state_layout]
import ../../../src/state/accumulation/current/[statistics as accumulation_current_statistics,
    driver as accumulation_current_driver, sequence as accumulation_current_sequence]
import ../../../src/state/accumulation/[coverage as accumulation_coverage,
    annulment as accumulation_annulment]
import ../../../src/state/store
import ../../support/[accumulation_current_statistics_context, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc main() {.raises.} =
  ## Static reports still pass actual signature/admission and guest proof constructors before aggregation.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact binary report transport.
  let base = decodeOwnedReport(wire, 2).value
  let completed = currentStatisticsCompletion(base, CurrentStatisticsScenario.Transfers)
  failHash(1)
  let prepared = prepareCurrentAccumulationStatistics(completed, currentStatisticsLimits())
  assert prepared.error == CurrentAccumulationStatisticsError.None, $prepared.error
  assert hashCalls() == 0, "statistics use exact owned counts without hashing or state writes"
  failHash(0)
  let statistics = prepared.value
  let info = statistics.currentStatisticsInfo.value
  assert info.entries == 3 and info.providers == 4 and info.services == 2
  assert uint64(info.reports) == 1 and uint64(info.operands) == 1 and uint64(info.transfers) == 1
  let first = statistics.currentStatisticsAt(StatisticsServiceIndex(0)).value
  let second = statistics.currentStatisticsAt(StatisticsServiceIndex(1)).value
  assert uint32(first.service) == 42 and uint32(second.service) == 99
  assert uint64(first.statistics.counters[ServiceMeasure.AccumulationCount]) == 1
  assert uint64(first.statistics.counters[ServiceMeasure.TransferCount]) == 0
  assert uint64(second.statistics.counters[ServiceMeasure.AccumulationCount]) == 0
  assert uint64(second.statistics.counters[ServiceMeasure.TransferCount]) == 1
  assert uint64(second.statistics.accumulationGas) == 44, "initial and funded held-transfer halts each spend22"
  assert uint64(info.gasUsed) == uint64(first.statistics.accumulationGas)+44
  var copy = first
  copy.statistics.accumulationGas = ActivityGas(high(uint64))
  assert uint64(statistics.currentStatisticsAt(StatisticsServiceIndex(
      0)).value.statistics.accumulationGas) != high(uint64)
  for measure in [ServiceMeasure.ProvisionCount, ServiceMeasure.ProvisionBytes,
      ServiceMeasure.RefinementCount, ServiceMeasure.Imports, ServiceMeasure.Exports]:
    assert uint64(first.statistics.counters[measure]) == 0, "unrelated activity remains separate"
  let missingWork = currentStatisticsCompletion(base, CurrentStatisticsScenario.SkippedReport)
  let skipped = prepareCurrentAccumulationStatistics(missingWork, currentStatisticsLimits()).value
  assert skipped.currentStatisticsInfo.value.services == 1
  let skippedRow = skipped.currentStatisticsAt(StatisticsServiceIndex(0)).value
  assert uint32(skippedRow.service) == 42 and uint64(skippedRow.statistics.accumulationGas) == 0
  assert uint64(skippedRow.statistics.counters[ServiceMeasure.AccumulationCount]) == 1, "unavailable code still processes its real work item"
  let allZero = currentStatisticsCompletion(base, CurrentStatisticsScenario.ZeroParticipants)
  var zeroPolicy = currentStatisticsLimits()
  zeroPolicy.services = ElementLimit(0)
  zeroPolicy.gas = Gas(0)
  let zero = prepareCurrentAccumulationStatistics(allZero, zeroPolicy).value
  assert zero.currentStatisticsInfo.value.providers == 2 and
      zero.currentStatisticsInfo.value.services == 0, "all-zero participants are omitted only after genuine complete traversal"
  let ejected = currentStatisticsCompletion(base, CurrentStatisticsScenario.EjectedTransfer)
  let deleted = prepareCurrentAccumulationStatistics(ejected, currentStatisticsLimits()).value
  let missing = deleted.currentStatisticsAt(StatisticsServiceIndex(1)).value
  assert uint32(missing.service) == 99 and uint64(missing.statistics.accumulationGas) == 0
  assert uint64(missing.statistics.counters[ServiceMeasure.TransferCount]) == 1, "accepted transfer to absent recipient remains counted"
  assert ejected.completedSequenceState.value.lookup(chapterServiceKey(StateChapter(255),
      missing.service)).error == StateStoreError.MissingKey
  let history = ejected.completedSequenceSource.value
  assert history.currentSequenceCoverageAt(CurrentSequenceEntryIndex(
      1)).value.coverageInfo.value.absent == 1
  let canceled = currentStatisticsCompletion(base, CurrentStatisticsScenario.Annulled)
  let canceledCoverage = canceled.completedSequenceSource.value.currentSequenceCoverageAt(
      CurrentSequenceEntryIndex(0)).value
  assert canceledCoverage.coverageAnnulment.value.annulmentInfo.value.annulled == 1
  let original = prepareCurrentAccumulationStatistics(canceled, currentStatisticsLimits()).value
  let junior = original.currentStatisticsAt(StatisticsServiceIndex(1)).value
  assert uint64(junior.statistics.accumulationGas) > 575, "annulled original gas is never refunded in G(s)"
  for mode in 0..<6:
    var limits = currentStatisticsLimits()
    case mode
    of 0: limits.entries = ElementLimit(2) # Every actual entry must be inspected.
    of 1: limits.providers = ElementLimit(3) # Skipped/zero provider visits also consume work capacity.
    of 2: limits.operands = ElementLimit(0) # N counts processed work regardless of actual gas.
    of 3: limits.transfers = ElementLimit(0) # X counts zero-token and absent-recipient records.
    of 4: limits.services = ElementLimit(1) # Nonzero dictionary capture cannot truncate a service.
    else: limits.gas = Gas(0) # Gross original gas has its own local representation/usage bound.
    assert prepareCurrentAccumulationStatistics(completed, limits).error ==
        CurrentAccumulationStatisticsError.LimitExceeded
  assert statistics.currentStatisticsAt(StatisticsServiceIndex(high(uint64))).error ==
      CurrentAccumulationStatisticsError.InvalidIndex
  let refused = prepareCurrentAccumulationStatistics(default(CompletedCurrentAccumulationSequence),
      currentStatisticsLimits())
  assert refused.error == CurrentAccumulationStatisticsError.InvalidSource
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCurrentAccumulationStatistics(completed, currentStatisticsLimits()).value
    assert local.currentStatisticsInfo.value.services ==
        2 # Fixed copied delta rows and terminal source ownership release together.
  let after = getOccupiedMem()
  assert occupied == after, "current accumulation statistics release"
  recordArcRelease("pvm_current_accumulation_statistics", 1000, occupied, after)
  echo "PVM current accumulation statistics passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Admission, native setup and unexpected failures must fail the suite.
except:
  quit(2)
