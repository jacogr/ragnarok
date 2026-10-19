# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive fresh per-block core metrics from incoming work, available data and original assurance bits.
## Pure rows are caller-owned; opaque preparation retains exact report-admission provenance without state writes.

import ../codec/[bounded, owned, report_owned, state_statistics, assurances, block_codec]
import ./[report_admission, guarantee_credentials, block_transition, block_admission, availability]

type
  CoreActivityConfig* = object ## Independent output, descriptor, digest, encoded and bit-work ceilings.
    cores*, incoming*, available*, digests*, assurances*, assuranceBits*: ElementLimit
    assuranceBytes*: ByteLimit ## Preparation bounds the original encoded component before reading votes.
  CoreActivityInfo* = object ## Copied actual populations; bit work includes all profile bits of every assurance.
    cores*, incoming*, available*, digests*, assurances*: int
  CoreActivityProjection* = object ## Unverified borrowed-input projection; never an admission certificate.
    info*: CoreActivityInfo
    values*: seq[CoreActivity]
  CoreActivityError* {.pure.} = enum ## Refusals contain only reasons, never partial metrics or source handles.
    Uninitialized,     ## Default result or prepared owner.
    None,              ## Complete selected success permits extraction.
    InvalidSource,     ## No genuine report-admission source.
    InvalidConfig,     ## Core profile is outside the supported 2..341 domain.
    InvalidInput,      ## Default report owner has no inspectable metadata.
    InvalidCore,       ## Report core lies outside the selected profile.
    InvalidAssurances, ## Raw assurance padding contains out-of-profile bits.
    InvalidIndex,      ## Full-width core ordinal exceeds the retained rows.
    LimitExceeded,     ## Independent work, capture or output ceiling was exceeded.
    CounterOverflow    ## A mathematical natural or gas sum cannot fit uint64.
  ActivityData = ref object # Private acyclic source retention and immutable fixed core rows.
    source: AdmittedReports
    info: CoreActivityInfo
    values: seq[CoreActivity]
  PreparedCoreActivity* = object ## Certifies original-block metric provenance, not complete C(13) or block validity.
    data: nil ActivityData
  CoreActivityResult*[T] = object ## Only explicitly selected success carries an extractable payload.
    case status: CoreActivityError
    of None:
      completed: T                # Neither payload nor discriminator may be retagged externally.
    else:
      discard                     # No prefix escapes a failed sum or policy check.

func error*[T](outcome: CoreActivityResult[T]): CoreActivityError =
  ## Read the selected reason without exposing mutation.
  outcome.status
func value*[T](outcome: CoreActivityResult[T]): T {.inline,
    requires: outcome.status == CoreActivityError.None.} =
  ## Extract complete success under checked optimized builds.
  outcome.completed
func populations(cores: CoreCount, incoming, available, assurances: int,
    config: CoreActivityConfig): bool =
  ## Bound descriptor materialization and multiplication before allocation or bit traversal.
  uint64(cores) <= uint64(config.cores) and
    uint64(incoming) <= uint64(config.incoming) and incoming <= high(int) div sizeof(
        OwnedReport) and
    uint64(available) <= uint64(config.available) and available <= high(int) div sizeof(
        OwnedReport) and
    uint64(assurances) <= uint64(config.assurances) and assurances <= high(int) div sizeof(
        Assurance) and
    uint64(assurances) <= uint64(config.assuranceBits) div uint64(cores)
proc add(target: var ActivityNatural, amount: uint64): bool =
  ## Prove the natural sum before modifying private scratch.
  if amount > high(uint64)-uint64(target): return false # Local representation refusal, never wrapping.
  target = ActivityNatural(uint64(target)+amount)
  true

proc projectCoreActivity*(cores: CoreCount, incoming, available: openArray[OwnedReport],
    assurances: openArray[Assurance], config: CoreActivityConfig): CoreActivityResult[
        CoreActivityProjection] =
  ## Borrow stable raw inputs; signatures/uniqueness require genuine source preparation, not this projection.
  template fail(reason: CoreActivityError) =
    ## Return only the selected reason; no scratch row or retained source escapes.
    return CoreActivityResult[CoreActivityProjection](status: reason)
  if uint64(cores) < 2 or uint64(cores) > 341: fail(CoreActivityError.InvalidConfig)
  if not populations(cores, incoming.len, available.len, assurances.len, config):
    fail(CoreActivityError.LimitExceeded) # Every logical traversal has a bounded population.
  var digests = 0
  for family in 0..<2:
    let reports = if family == 0: incoming else: available # Distinct families share only metadata validation.
    for report in reports:
      let facts = report.ownedReportInfo
      if facts.error != OwnershipError.None: fail(CoreActivityError.InvalidInput)
      if uint64(facts.value.core) >= uint64(cores): fail(CoreActivityError.InvalidCore)
      if family == 0:
        if uint64(facts.value.digestCount) > uint64(config.digests)-uint64(digests) or
            facts.value.digestCount > high(int)-digests:
          fail(CoreActivityError.LimitExceeded) # Available reports contribute no refinement digest work.
        digests += facts.value.digestCount
  let count = int(uint64(cores))
  for assurance in assurances:
    for index, octet in assurance.bits.bytes:
      let first = index*8
      if first >= count:
        if octet != 0: fail(CoreActivityError.InvalidAssurances) # Entire unused bytes must remain zero.
      elif count-first < 8:
        if (octet shr (count-first)) != 0: fail(CoreActivityError.InvalidAssurances) # Reject upper padding bits.
  var rows = newSeq[CoreActivity](count)
  for report in incoming:
    let facts = report.ownedReportInfo.value
    let index = int(uint64(facts.core))
    if not add(rows[index].counters[CoreMeasure.BundleBytes], uint64(facts.header.bundleLength)):
      fail(CoreActivityError.CounterOverflow)
    for ordinal in 0..<facts.digestCount:
      let usage = report.ownedReportDigest(ordinal).value.refine
      if not add(rows[index].counters[CoreMeasure.Imports], uint64(usage.imports)) or
          not add(rows[index].counters[CoreMeasure.ExtrinsicCount], uint64(usage.extrinsicCount)) or
          not add(rows[index].counters[CoreMeasure.ExtrinsicBytes], uint64(usage.extrinsicSize)) or
          not add(rows[index].counters[CoreMeasure.Exports], uint64(usage.exports)) or
          uint64(usage.gasUsed) > high(uint64)-uint64(rows[index].gas):
        fail(CoreActivityError.CounterOverflow) # All failed-work usage is included; authorization gas is excluded.
      rows[index].gas = ActivityGas(uint64(rows[index].gas)+uint64(usage.gasUsed))
  for report in available:
    let facts = report.ownedReportInfo.value
    # uint16 segments and uint32 bundle bytes prove both products and the combined DA term fit uint64.
    let padded = (uint64(facts.header.segmentCount)*65+63) div 64
    let load = uint64(facts.header.bundleLength)+4104*padded
    if not add(rows[int(uint64(facts.core))].counters[CoreMeasure.DataAvailabilityLoad], load):
      fail(CoreActivityError.CounterOverflow)
  for assurance in assurances:
    for index in 0..<count:
      if (assurance.bits.bytes[index div 8] and (1'u8 shl (index mod 8))) != 0:
        if not add(rows[index].counters[CoreMeasure.Popularity], 1):
          fail(CoreActivityError.CounterOverflow) # Count every original bit independently of availability threshold.
  CoreActivityResult[CoreActivityProjection](status: CoreActivityError.None,
    completed: CoreActivityProjection(values: rows, info: CoreActivityInfo(cores: count,
      incoming: incoming.len, available: available.len, digests: digests,
      assurances: assurances.len)))

proc coreActivityInfo*(plan: PreparedCoreActivity): CoreActivityResult[CoreActivityInfo] =
  ## Copy actual bounded populations without exposing storage.
  let data = plan.data
  if data == nil: return CoreActivityResult[CoreActivityInfo](
      status: CoreActivityError.Uninitialized)
  CoreActivityResult[CoreActivityInfo](status: CoreActivityError.None, completed: data.info)
proc coreActivitySource*(plan: PreparedCoreActivity): CoreActivityResult[AdmittedReports] =
  ## Retain the exact original signed block and staged availability independently of caller handles.
  let data = plan.data
  if data == nil: return CoreActivityResult[AdmittedReports](
      status: CoreActivityError.Uninitialized)
  CoreActivityResult[AdmittedReports](status: CoreActivityError.None, completed: data.source)
proc coreActivityAt*(plan: PreparedCoreActivity, index: StatisticsCoreIndex): CoreActivityResult[CoreActivity] =
  ## Copy one core tuple after a full-width nominal ordinal bound check.
  let data = plan.data
  if data == nil: return CoreActivityResult[CoreActivity](
      status: CoreActivityError.Uninitialized)
  if uint64(index) >= uint64(data.values.len):
    return CoreActivityResult[CoreActivity](status: CoreActivityError.InvalidIndex)
  CoreActivityResult[CoreActivity](status: CoreActivityError.None, completed: data.values[int(
      uint64(index))])

proc prepareCoreActivity*(source: AdmittedReports, config: CoreActivityConfig): CoreActivityResult[
    PreparedCoreActivity] =
  ## Derive all input families and the profile from one genuine admission; never accept substituted raw contexts.
  template fail(reason: CoreActivityError) =
    ## Return only the selected reason; no scratch row or retained source escapes.
    return CoreActivityResult[PreparedCoreActivity](status: reason)
  let staged = source.reportBlockStage
  if staged.error != ReportAdmissionError.None: fail(CoreActivityError.InvalidSource)
  let stage = staged.value
  let cores = stage.blockTransitionProfile.cores
  let credentials = source.reportCredentials.value
  let incomingCount = credentials.verifiedGuaranteeCount.value
  let availableCount = stage.value.availability.availableReportCount
  let component = stage.value.admitted.admittedBlock.blockExtrinsic.value.extrinsicAssurances.value
  let facts = component.componentInfo.value
  if not populations(cores, incomingCount, availableCount, facts.records, config) or
      uint64(facts.consumed) > uint64(config.assuranceBytes):
    fail(CoreActivityError.LimitExceeded) # Encoded bytes and descriptor/bit work precede component materialization.
  var incoming = newSeq[OwnedReport](incomingCount)
  for index in 0..<incoming.len: incoming[index] = credentials.verifiedGuaranteeAt(
      index).value.report
  var available = newSeq[OwnedReport](availableCount)
  for index in 0..<available.len: available[index] = stage.value.availability.availableReportAt(index).value
  let projected = projectCoreActivity(cores, incoming, available, component.readAssurances.value, config)
  if projected.error != CoreActivityError.None: fail(projected.error)
  CoreActivityResult[PreparedCoreActivity](status: CoreActivityError.None,
    completed: PreparedCoreActivity(data: ActivityData(source: source,
      info: projected.value.info, values: projected.value.values)))
