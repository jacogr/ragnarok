# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Coordinate per-block refinement, provision and accumulation service metrics from genuine original-block provenance.
## Pure projections own fixed rows; opaque preparation retains finalized statistics without publishing C(13) or state.

import std/algorithm
import ../../codec/[bounded, composite, owned, report_owned]
import ../../codec/state/statistics as state_statistics
import ../../codec/block_codec
import ../accumulation/[statistics as accumulation_statistics,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../report/admission as report_admission
import ../guarantee_credentials
import "../block/transition" as block_transition
import "../block/admission" as block_admission

type
  ServiceActivityConfig* = object ## Independent inspected populations and retained rows bound all materialization/work.
    reports*, digests*, preimages*, accumulation*, services*: ElementLimit
    preimageFrameBytes*, preimageBytes*: ByteLimit
  ServiceActivityInfo* = object ## Copied populations distinguish incoming reports from processed accumulation rows.
    reports*, digests*, preimages*, accumulation*, services*: int
  ServiceActivityProjection* = object ## Caller-owned pure rows have no block or admission provenance certificate.
    info*: ServiceActivityInfo
    values*: seq[ServiceStatisticsEntry]
  ServiceActivityError* {.pure.} = enum ## Defaults/refusals carry only reasons, never prior rows or a source prefix.
    Uninitialized,       ## Default result or prepared owner.
    None,                ## Complete selected success permits extraction.
    InvalidSource,       ## No genuine accumulation statistics owner.
    InvalidInput,        ## Default report/preimage or wrong preimage schema.
    InvalidAccumulation, ## Noncanonical keys or fields outside an accumulation-only nonzero delta.
    InvalidIndex,        ## Full-width dictionary ordinal is outside the retained rows.
    LimitExceeded,       ## Inspected work, copied extents or retained service population exceeds policy.
    CounterOverflow      ## A per-service natural/gas sum exceeds its uint64 representation.
  # Private acyclic storage retains the exact finalized source and independent fixed coordinated metrics.
  ActivityData = ref object
    source: PreparedAccumulationStatistics
    values: seq[ServiceStatisticsEntry]
    info: ServiceActivityInfo
  PreparedServiceActivity* = object ## Original-block-derived service metrics do not certify full preimage admissibility or complete C(13).
    data: nil ActivityData
  ServiceActivityResult*[T] = object ## Only selected success carries data; every default/refusal has reasons alone.
    case status: ServiceActivityError
    of None:
      completed: T # No mutable discriminator or payload is exported.
    else:
      discard      # Failure cannot masquerade as empty coordinated activity.

func error*[T](outcome: ServiceActivityResult[T]): ServiceActivityError =
  ## Inspect the selected reason without permitting retagging.
  outcome.status

func value*[T](outcome: ServiceActivityResult[T]): T {.inline,
    requires: outcome.status == ServiceActivityError.None.} =
  ## Extract only complete selected success in checked optimized builds.
  outcome.completed

proc charge(total: var int, count: int, limit: ElementLimit): bool =
  ## Bound combined fixed candidate storage and logical work before any aggregate addition.
  if uint64(count) > uint64(limit)-uint64(total) or count > high(int) div sizeof(
      ServiceStatisticsEntry)-total:
    return false # Earlier successful charges establish nonnegative subtraction operands.
  total += count
  true

func compareService(left, right: ServiceStatisticsEntry): int =
  ## Numeric identity alone determines canonical dictionary order, independent of report arrival.
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0

proc combine(left: var ServiceActivity, right: ServiceActivity): bool =
  ## Failed aggregation mutates only private scratch; no partially combined row can escape.
  for measure in low(ServiceMeasure)..high(ServiceMeasure):
    let value = uint64(right.counters[measure])
    if value > high(uint64)-uint64(left.counters[measure]): return false # Prove each natural before addition.
    left.counters[measure] = ActivityNatural(uint64(left.counters[measure])+value)
  if uint64(right.refinementGas) > high(uint64)-uint64(left.refinementGas) or
      uint64(right.accumulationGas) > high(uint64)-uint64(left.accumulationGas):
    return false # Both gas domains are independently bounded, never saturated or wrapped.
  left.refinementGas = ActivityGas(uint64(left.refinementGas)+uint64(right.refinementGas))
  left.accumulationGas = ActivityGas(uint64(left.accumulationGas)+uint64(right.accumulationGas))
  true

proc projectServiceActivity*(reports: openArray[OwnedReport], preimages: OwnedFrame,
    accumulation: openArray[ServiceStatisticsEntry],
        config: ServiceActivityConfig): ServiceActivityResult[ServiceActivityProjection] =
  ## Borrow stable source arrays, inspect owned metadata only, and return independent fixed tuples without hashing.
  template fail(reason: ServiceActivityError) =
    return ServiceActivityResult[ServiceActivityProjection](status: reason)
  if uint64(reports.len) > uint64(config.reports) or uint64(accumulation.len) > uint64(
      config.accumulation):
    fail(ServiceActivityError.LimitExceeded) # Bound even empty reports and accumulation traversal before inspecting sources.
  let provided = preimages.ownedInfo
  if provided.error != OwnershipError.None or provided.value.kind != OwnedKind.Preimages:
    fail(ServiceActivityError.InvalidInput) # A default/byte/work owner is not an empty preimage family.
  if uint64(provided.value.blobCount) > uint64(config.preimages) or
      uint64(provided.value.consumed) > uint64(config.preimageFrameBytes):
    fail(ServiceActivityError.LimitExceeded) # Count and complete encoded bytes have separate capture ceilings.
  var digests = 0
  for report in reports:
    let facts = report.ownedReportInfo
    if facts.error != OwnershipError.None: fail(ServiceActivityError.InvalidInput)
    if not charge(digests, facts.value.digestCount, config.digests):
      fail(ServiceActivityError.LimitExceeded) # Count every digest, including failed refinement outputs.
  var count = digests
  if not charge(count, provided.value.blobCount, ElementLimit(high(uint64))) or
      not charge(count, accumulation.len, ElementLimit(high(uint64))):
    fail(ServiceActivityError.LimitExceeded) # Combined native extent precedes candidate allocation.
  var bytes = 0'u64
  for index in 0..<provided.value.blobCount:
    let length = uint64(preimages.ownedBlobLength(index).value)
    if length > uint64(config.preimageBytes)-bytes: fail(ServiceActivityError.LimitExceeded)
    bytes += length # Preflight payload metrics without reading or copying any payload octets.
  for index, row in accumulation:
    if index > 0 and uint32(accumulation[index-1].service) >= uint32(row.service):
      fail(ServiceActivityError.InvalidAccumulation) # Require a numeric sorted unique accumulation mapping.
    var active = uint64(row.statistics.accumulationGas) != 0
    for measure in low(ServiceMeasure)..high(ServiceMeasure):
      let value = uint64(row.statistics.counters[measure])
      if measure in {ServiceMeasure.AccumulationCount, ServiceMeasure.TransferCount}:
        active = active or value != 0 # Only these counters belong to the accumulation delta.
      elif value != 0:
        fail(ServiceActivityError.InvalidAccumulation) # Prevent double-counting unrelated activity families.
    if uint64(row.statistics.refinementGas) != 0 or not active:
      fail(ServiceActivityError.InvalidAccumulation) # Zero tuples are not keys of the certified nonzero delta.
  var rows = newSeq[ServiceStatisticsEntry](count)
  var cursor = 0
  for report in reports:
    for index in 0..<report.ownedReportInfo.value.digestCount:
      let digest = report.ownedReportDigest(index).value
      var activity = ServiceActivity(refinementGas: ActivityGas(uint64(digest.refine.gasUsed)))
      activity.counters[ServiceMeasure.RefinementCount] = ActivityNatural(1)
      activity.counters[ServiceMeasure.Imports] = ActivityNatural(uint64(digest.refine.imports))
      activity.counters[ServiceMeasure.ExtrinsicCount] = ActivityNatural(uint64(
          digest.refine.extrinsicCount))
      activity.counters[ServiceMeasure.ExtrinsicBytes] = ActivityNatural(uint64(
          digest.refine.extrinsicSize))
      activity.counters[ServiceMeasure.Exports] = ActivityNatural(uint64(digest.refine.exports))
      rows[cursor] = ServiceStatisticsEntry(service: digest.service, statistics: activity)
      inc cursor # All digest descriptors were preflighted before allocation.
  for index in 0..<provided.value.blobCount:
    var activity = ServiceActivity()
    activity.counters[ServiceMeasure.ProvisionCount] = ActivityNatural(1)
    activity.counters[ServiceMeasure.ProvisionBytes] = ActivityNatural(uint64(
        preimages.ownedBlobLength(index).value))
    rows[cursor] = ServiceStatisticsEntry(service: preimages.ownedService(index).value,
        statistics: activity)
    inc cursor # Empty payloads still contribute one provision record.
  for row in accumulation:
    rows[cursor] = row
    inc cursor # Copy the validated accumulation-only tuple without changing its three fields.
  rows.sort(compareService)
  var groups = 0
  for index in 0..<rows.len:
    let row = rows[index]
    if groups == 0 or compareService(row, rows[groups-1]) != 0:
      rows[groups] = row
      inc groups # Every input family contributes a key even when all its non-count metrics are zero.
    else:
      var combined = rows[groups-1]
      if not combine(combined.statistics, row.statistics): fail(
          ServiceActivityError.CounterOverflow)
      rows[groups-1] = combined # Only complete fieldwise aggregation updates this private group.
  if uint64(groups) > uint64(config.services): fail(ServiceActivityError.LimitExceeded)
  var values = newSeq[ServiceStatisticsEntry](groups)
  for index in 0..<groups: values[index] = rows[index] # Return exact-sized independent fixed records.
  ServiceActivityResult[ServiceActivityProjection](status: ServiceActivityError.None,
    completed: ServiceActivityProjection(values: values, info: ServiceActivityInfo(
      reports: reports.len,
      digests: digests, preimages: provided.value.blobCount, accumulation: accumulation.len,
      services: groups)))

proc serviceActivityInfo*(plan: PreparedServiceActivity): ServiceActivityResult[
    ServiceActivityInfo] =
  ## Copy bounded source populations and retained row cardinality.
  let data = plan.data
  if data == nil: return ServiceActivityResult[ServiceActivityInfo](
      status: ServiceActivityError.Uninitialized)
  ServiceActivityResult[ServiceActivityInfo](status: ServiceActivityError.None,
      completed: data.info)

proc serviceActivitySource*(plan: PreparedServiceActivity): ServiceActivityResult[
    PreparedAccumulationStatistics] =
  ## Retain exact finalized accumulation and its original block graph independently of caller handles.
  let data = plan.data
  if data == nil: return ServiceActivityResult[PreparedAccumulationStatistics](
      status: ServiceActivityError.Uninitialized)
  ServiceActivityResult[PreparedAccumulationStatistics](status: ServiceActivityError.None,
      completed: data.source)

proc serviceActivityAt*(plan: PreparedServiceActivity,
    index: StatisticsServiceIndex): ServiceActivityResult[ServiceStatisticsEntry] =
  ## Copy one complete tuple at a checked nominal dictionary ordinal, never a protocol service ID.
  let data = plan.data
  if data == nil: return ServiceActivityResult[ServiceStatisticsEntry](
      status: ServiceActivityError.Uninitialized)
  if uint64(index) >= uint64(data.values.len): return ServiceActivityResult[ServiceStatisticsEntry](
      status: ServiceActivityError.InvalidIndex)
  ServiceActivityResult[ServiceStatisticsEntry](status: ServiceActivityError.None,
      completed: data.values[int(uint64(index))])

proc prepareServiceActivity*(source: PreparedAccumulationStatistics,
    config: ServiceActivityConfig): ServiceActivityResult[PreparedServiceActivity] =
  ## Derive every family from one genuine finalized source; do not accept foreign report or preimage arrays.
  let facts = source.statisticsInfo
  if facts.error != AccumulationStatisticsError.None:
    return ServiceActivityResult[PreparedServiceActivity](
        status: ServiceActivityError.InvalidSource)
  let initial = source.statisticsSource.value.finalAccumulationOutputs.value.outputsSource.value
  let admission = initial.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
  let credentials = admission.reportCredentials.value
  let reports = credentials.verifiedGuaranteeCount.value
  let provided = admission.reportBlockStage.value.value.admitted.admittedBlock.blockExtrinsic.value.extrinsicPreimages.value
  let preimageInfo = provided.componentInfo.value
  if uint64(reports) > uint64(config.reports) or reports > high(int) div sizeof(OwnedReport) or
      uint64(facts.value.services) > uint64(config.accumulation) or facts.value.services > high(
          int) div sizeof(ServiceStatisticsEntry) or
      uint64(preimageInfo.records) > uint64(config.preimages) or preimageInfo.records > high(
          int) div sizeof(ServiceStatisticsEntry) or
      uint64(preimageInfo.consumed) > uint64(config.preimageFrameBytes):
    return ServiceActivityResult[PreparedServiceActivity](
        status: ServiceActivityError.LimitExceeded) # Preflight before materializing owners or copying descriptors.
  var incoming = newSeq[OwnedReport](reports)
  for index in 0..<reports: incoming[index] = credentials.verifiedGuaranteeAt(index).value.report
  var accumulation = newSeq[ServiceStatisticsEntry](facts.value.services)
  for index in 0..<accumulation.len: accumulation[index] = source.statisticsAt(
      StatisticsServiceIndex(uint64(index))).value
  let projected = projectServiceActivity(incoming, provided.readPreimages.value, accumulation, config)
  if projected.error != ServiceActivityError.None:
    return ServiceActivityResult[PreparedServiceActivity](
        status: projected.error) # No prefix/source survives projection refusal.
  ServiceActivityResult[PreparedServiceActivity](status: ServiceActivityError.None,
    completed: PreparedServiceActivity(data: ActivityData(source: source,
        values: projected.value.values, info: projected.value.info)))
