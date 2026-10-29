# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 C(13): pure per-block core/service activity from explicit incoming/available reports, votes, provisions and S.
## Immutable fixed rows certify no block/eligibility provenance and publish no map; every per-block field starts at zero.

import std/algorithm
import ../../codec/[bounded, assurances, report_owned, owned]
import ../../codec/work/digest as work_digest
import ../../codec/state/statistics as state_statistics
from ../preimages import PreimageProvision

type
  CoreServiceActivityConfig* = object ## Explicit chain core ceiling and independent traversal/storage policies.
    cores*: CoreCount ## Supported 2..341 profile; no other chain domains are inferred.
    incoming*, available*, digests*, assurances*: ElementLimit ## Distinct report roles, incoming digest work and raw votes.
    provisions*, accumulation*, services*: ElementLimit ## Provided-service groups, S keys and retained union cardinality.
  CoreServiceActivityInfo* = object ## Copied traversed populations and retained fixed-row counts.
    cores*, incoming*, available*, digests*, assurances*: int
    provisions*, accumulation*, services*: int
  CoreServiceActivityError* {.pure.} = enum ## Only complete success contains a projection or fixed tuple.
    Uninitialized, None, InvalidConfig, InvalidSource, InvalidCore, InvalidIndex,
    NonCanonical, InvalidContribution, LimitExceeded, CounterOverflow
  ActivityData = ref object # Acyclic independent fixed storage retains no borrowed lists or report owners.
    cores: seq[CoreActivity]
    services: seq[ServiceStatisticsEntry]
    info: CoreServiceActivityInfo
  CoreServiceActivityProjection* = object ## Explicit pure inputs establish no authenticated block certificate.
    data: nil ActivityData
  CoreServiceActivityResult*[T] = object ## Default/refused alternatives contain reasons alone, never an earlier partial union.
    case status: CoreServiceActivityError
    of None:
      completed: T # Supported optimized-build contracts guard all extraction.
    else:
      discard      # No partial per-core sums or earlier service groups escape refusal.

func error*[T](outcome: CoreServiceActivityResult[T]): CoreServiceActivityError =
  ## Inspect a read-only reason without writable discriminator access.
  outcome.status
func value*[T](outcome: CoreServiceActivityResult[T]): T {.inline,
    requires: outcome.status == CoreServiceActivityError.None.} =
  ## Extract only selected complete success.
  outcome.completed

proc coreServiceActivityInfo*(projection: CoreServiceActivityProjection): CoreServiceActivityResult[
    CoreServiceActivityInfo] =
  ## Copy work populations without returning retained arrays.
  let data = projection.data
  if data == nil:
    return CoreServiceActivityResult[CoreServiceActivityInfo](
        status: CoreServiceActivityError.Uninitialized)
  CoreServiceActivityResult[CoreServiceActivityInfo](status: CoreServiceActivityError.None,
    completed: data.info)

proc projectedCoreAt*(projection: CoreServiceActivityProjection, index: StatisticsCoreIndex):
    CoreServiceActivityResult[CoreActivity] =
  ## Copy one fixed core tuple after full-width nominal ordinal validation.
  let data = projection.data
  if data == nil:
    return CoreServiceActivityResult[CoreActivity](status: CoreServiceActivityError.Uninitialized)
  if uint64(index) >= uint64(data.cores.len):
    return CoreServiceActivityResult[CoreActivity](status: CoreServiceActivityError.InvalidIndex)
  CoreServiceActivityResult[CoreActivity](status: CoreServiceActivityError.None,
    completed: data.cores[int(uint64(index))])

proc projectedServiceAt*(projection: CoreServiceActivityProjection, index: StatisticsServiceIndex):
    CoreServiceActivityResult[ServiceStatisticsEntry] =
  ## Copy one numeric-service ordered key and fixed tuple at a checked dictionary ordinal.
  let data = projection.data
  if data == nil:
    return CoreServiceActivityResult[ServiceStatisticsEntry](
        status: CoreServiceActivityError.Uninitialized)
  if uint64(index) >= uint64(data.services.len):
    return CoreServiceActivityResult[ServiceStatisticsEntry](
        status: CoreServiceActivityError.InvalidIndex)
  CoreServiceActivityResult[ServiceStatisticsEntry](status: CoreServiceActivityError.None,
    completed: data.services[int(uint64(index))])

# All counts originate in validated owners or native borrowed extents; charge before adding.
proc charge(total: var int, amount: int, limit: ElementLimit): bool =
  if uint64(amount) > uint64(limit)-uint64(total) or amount > high(int)-total: return false
  total += amount
  true

# Wrapping compiler arithmetic requires explicit proof before every natural/gas aggregation.
proc add(target: var ActivityNatural, amount: uint64): bool =
  if amount > high(uint64)-uint64(target): return false
  target = ActivityNatural(uint64(target)+amount)
  true
proc add(target: var ActivityGas, amount: uint64): bool =
  if amount > high(uint64)-uint64(target): return false
  target = ActivityGas(uint64(target)+amount)
  true

# Dictionary order follows numeric service identity, independently of report arrival or wire byte order.
func compareService(left, right: ServiceStatisticsEntry): int =
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0

# S contains exactly its accumulation triple; unrelated per-block fields cannot silently become discarded old state.
proc validAccumulation(row: ServiceActivity): bool =
  for measure in ServiceMeasure.ProvisionCount..ServiceMeasure.Exports:
    if uint64(row.counters[measure]) != 0: return false
  if uint64(row.refinementGas) != 0: return false
  uint64(row.counters[ServiceMeasure.AccumulationCount]) != 0 or
    uint64(row.counters[ServiceMeasure.TransferCount]) != 0 or uint64(row.accumulationGas) != 0

proc projectCoreServiceActivity*(incoming, available: openArray[OwnedReport],
    assurances: openArray[Assurance], provisions: openArray[PreimageProvision],
    accumulation: openArray[ServiceStatisticsEntry], config: CoreServiceActivityConfig):
    CoreServiceActivityResult[CoreServiceActivityProjection] =
  ## Borrow stable explicit inputs synchronously; retain only independent fixed tuples after complete success.
  template fail(reason: CoreServiceActivityError) =
    return CoreServiceActivityResult[CoreServiceActivityProjection](status: reason)
  let coreCount = uint64(config.cores)
  if coreCount < 2 or coreCount > 341:
    fail(CoreServiceActivityError.InvalidConfig) # Prove native core-array extent and bitfield addressing.
  # Separate policy predicates remain short under the pinned formatter and precede all source traversal.
  if uint64(incoming.len) > uint64(config.incoming): fail(CoreServiceActivityError.LimitExceeded)
  if uint64(available.len) > uint64(config.available): fail(CoreServiceActivityError.LimitExceeded)
  if uint64(assurances.len) > uint64(config.assurances): fail(
      CoreServiceActivityError.LimitExceeded)
  if uint64(provisions.len) > uint64(config.provisions): fail(
      CoreServiceActivityError.LimitExceeded)
  if uint64(accumulation.len) > uint64(config.accumulation): fail(
      CoreServiceActivityError.LimitExceeded)
  if uint64(incoming.len) > coreCount or uint64(available.len) > coreCount:
    fail(CoreServiceActivityError.NonCanonical) # Each list independently admits at most one report per core.
  var seenIncoming = default(array[341, bool])
  var seenAvailable = default(array[341, bool])
  var digests = 0
  for report in incoming:
    let meta = report.ownedReportInfo
    if meta.error != OwnershipError.None: fail(CoreServiceActivityError.InvalidSource)
    let core = uint64(meta.value.core)
    if core >= coreCount: fail(CoreServiceActivityError.InvalidCore)
    if seenIncoming[int(core)]: fail(CoreServiceActivityError.NonCanonical)
    seenIncoming[int(core)] = true # Independent domains allow a newly available predecessor on the same core.
    if not charge(digests, meta.value.digestCount, config.digests):
      fail(CoreServiceActivityError.LimitExceeded) # Preflight all incoming digest work before candidate storage.
  for report in available:
    let meta = report.ownedReportInfo
    if meta.error != OwnershipError.None: fail(CoreServiceActivityError.InvalidSource)
    let core = uint64(meta.value.core)
    if core >= coreCount: fail(CoreServiceActivityError.InvalidCore)
    if seenAvailable[int(core)]: fail(CoreServiceActivityError.NonCanonical)
    seenAvailable[int(core)] = true # Available digests never enter refinement sums or service keys.
  for index in 0..<assurances.len:
    if index > 0 and uint16(assurances[index].validator) <= uint16(assurances[index-1].validator):
      fail(CoreServiceActivityError.NonCanonical) # Raw vote membership cannot be duplicated by repeating a signer.
    for octet in 0..<43:
      for bit in 0..<8:
        if octet*8+bit >= int(coreCount) and (assurances[index].bits.bytes[octet] and byte(
            1 shl bit)) != 0:
          fail(CoreServiceActivityError.NonCanonical) # No out-of-profile or padded availability bits.
  for index, provision in provisions:
    if index > 0 and uint32(provision.service) <= uint32(provisions[index-1].service):
      fail(CoreServiceActivityError.NonCanonical) # Per-service contributions are already grouped and numerically ordered.
    if uint64(provision.count) == 0:
      fail(CoreServiceActivityError.InvalidContribution) # A provided service requires at least one admitted item, even if empty.
  for index, row in accumulation:
    if index > 0 and uint32(row.service) <= uint32(accumulation[index-1].service):
      fail(CoreServiceActivityError.NonCanonical) # S is an ordered unique dictionary, never a second old-statistics input.
    if not validAccumulation(row.statistics):
      fail(CoreServiceActivityError.InvalidContribution) # Reject non-accumulation fields and omitted-zero violations.
  let capacity = high(int) div sizeof(ServiceStatisticsEntry)
  if digests > capacity or provisions.len > capacity-digests:
    fail(CoreServiceActivityError.LimitExceeded) # Bound combined scratch without wrapping native descriptor bytes.
  let partial = digests+provisions.len
  if accumulation.len > capacity-partial:
    fail(CoreServiceActivityError.LimitExceeded) # Prove final addition/allocation after both prior populations.
  var cores = newSeq[CoreActivity](int(coreCount))
  var rows = newSeq[ServiceStatisticsEntry](partial+accumulation.len)
  var cursor = 0
  for report in incoming:
    let meta = report.ownedReportInfo.value
    let core = int(uint64(meta.core))
    cores[core].counters[CoreMeasure.BundleBytes] = ActivityNatural(uint32(
        meta.header.bundleLength))
    for index in 0..<meta.digestCount:
      let digest = report.ownedReportDigest(index).value
      let load = digest.refine
      var statistics = ServiceActivity(refinementGas: ActivityGas(uint64(load.gasUsed)))
      statistics.counters[ServiceMeasure.RefinementCount] = ActivityNatural(1)
      statistics.counters[ServiceMeasure.Imports] = ActivityNatural(uint64(load.imports))
      statistics.counters[ServiceMeasure.ExtrinsicCount] = ActivityNatural(uint64(
          load.extrinsicCount))
      statistics.counters[ServiceMeasure.ExtrinsicBytes] = ActivityNatural(uint64(
          load.extrinsicSize))
      statistics.counters[ServiceMeasure.Exports] = ActivityNatural(uint64(load.exports))
      rows[cursor] = ServiceStatisticsEntry(service: digest.service, statistics: statistics)
      inc cursor # Complete preflight bounded one candidate per incoming digest, regardless of output kind.
      var sum = cores[core]
      if not add(sum.counters[CoreMeasure.Imports], uint64(load.imports)) or
          not add(sum.counters[CoreMeasure.ExtrinsicCount], uint64(load.extrinsicCount)) or
          not add(sum.counters[CoreMeasure.ExtrinsicBytes], uint64(load.extrinsicSize)) or
          not add(sum.counters[CoreMeasure.Exports], uint64(load.exports)) or
          not add(sum.gas, uint64(load.gasUsed)):
        fail(CoreServiceActivityError.CounterOverflow) # No partial core or service candidate survives late overflow.
      cores[core] = sum
  for report in available:
    let meta = report.ownedReportInfo.value
    # E2 segment count bounds 65*n+63 below 2^23; padded segments*4104 plus E4 bundle length fits uint64.
    let segments = uint64(uint16(meta.header.segmentCount))
    let padded = (segments*65+63) div 64
    let bytes = uint64(uint32(meta.header.bundleLength))+4104*padded
    cores[int(uint64(meta.core))].counters[CoreMeasure.DataAvailabilityLoad] = ActivityNatural(bytes)
  for assurance in assurances:
    for core in 0..<int(coreCount):
      if (assurance.bits.bytes[core div 8] and byte(1 shl (core mod 8))) != 0:
        if not add(cores[core].counters[CoreMeasure.Popularity], 1):
          fail(CoreServiceActivityError.CounterOverflow) # Every raw bit contributes, even for a core with no report.
  for provision in provisions:
    var statistics = ServiceActivity()
    statistics.counters[ServiceMeasure.ProvisionCount] = ActivityNatural(uint64(provision.count))
    statistics.counters[ServiceMeasure.ProvisionBytes] = ActivityNatural(uint64(provision.bytes))
    rows[cursor] = ServiceStatisticsEntry(service: provision.service, statistics: statistics)
    inc cursor # Native candidate preflight includes every grouped provision row.
  for row in accumulation:
    rows[cursor] = row # Fixed copies preserve all three S fields without borrowing caller arrays.
    inc cursor
  rows.sort(compareService)
  var groups = 0
  for index in 0..<rows.len:
    let row = rows[index]
    if groups == 0 or compareService(row, rows[groups-1]) != 0:
      if uint64(groups) >= uint64(config.services): fail(CoreServiceActivityError.LimitExceeded)
      rows[groups] = row
      inc groups # Every union member has a positive refinement/provision count or nonzero S triple.
    else:
      var combined = rows[groups-1]
      for measure in low(ServiceMeasure)..high(ServiceMeasure):
        if not add(combined.statistics.counters[measure], uint64(row.statistics.counters[measure])):
          fail(CoreServiceActivityError.CounterOverflow) # Service sums may overflow across individually valid core totals.
      if not add(combined.statistics.refinementGas, uint64(row.statistics.refinementGas)) or
          not add(combined.statistics.accumulationGas, uint64(row.statistics.accumulationGas)):
        fail(CoreServiceActivityError.CounterOverflow) # Checked gas domains remain distinct from natural counters.
      rows[groups-1] = combined
  var services = newSeq[ServiceStatisticsEntry](groups)
  for index in 0..<groups: services[index] = rows[index] # Retain no oversized candidate scratch or report owners.
  CoreServiceActivityResult[CoreServiceActivityProjection](status: CoreServiceActivityError.None,
    completed: CoreServiceActivityProjection(data: ActivityData(cores: cores, services: services,
      info: CoreServiceActivityInfo(cores: int(coreCount), incoming: incoming.len,
        available: available.len, digests: digests, assurances: assurances.len,
        provisions: provisions.len, accumulation: accumulation.len, services: groups))))
