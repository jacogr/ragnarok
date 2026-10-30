# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex contextual validity: recent tuple and retained
## ancestor/child proof. These immutable read-only stages do not prove consensus ancestry or
## publish C(10).
##
## Exposes recent and lookup-anchor checks and immutable access to their certified
## policy/history context.

import ../../codec/bounded
import ../../codec/state/[history as state_history, safrole as state_safrole]
import ../../codec/[header, report_owned]
import ../ancestor_context
import ../fuzz/[ancestry as fuzz_ancestry, protocol as fuzz_protocol]
import ./policy as report_policy
import ../guarantee_credentials

type
  LookupAge* = distinct uint64 ## Lookup age is measured in timeslots, independently of the eight recent blocks.
  ReportAnchorConfig* = object ## Exact corrected C(3) decoding and explicit chain-specific lookup age.
    history*: HistoryConfig
    lookupAge*: LookupAge
  AncestorConfig* = object ## Independent retained-header count, per-header profile and aggregate serialized-byte ceilings.
    header*: HeaderConfig
    headers*: ElementLimit
    maxBytes*: ByteLimit
  ReportAnchorError* {.pure.} = enum ## Failed/default stages contain a reason alone, never a partially validated batch or chain.
    Uninitialized, None, InvalidPolicy, InvalidHistory, InvalidConfig, InvalidSlot,
    LimitExceeded, InvalidRecentAnchor, LookupTooOld, InvalidRecent,
    InvalidHeader, BrokenAncestry, MissingLookupAnchor, WrongLookupState, BackendFailure
  ## Acyclic owner retains the exact preceding policy, corrected history and candidate timeslot.
  RecentData = ref object
    policy: PolicyCheckedReports
    history: HistorySnapshot
    slot: StateTime
  RecentAnchoredReports* = object ## Recent/age validation is deliberately distinct from a completed ancestor proof.
    data: nil RecentData
  ## Final owner retains each checked full sealed header and the entire previous stage.
  AnchorData = ref object
    recent: RecentAnchoredReports
    context: AncestorContext
    fuzzContext: FuzzAncestry
    fuzzOrigin: bool
  AnchoredReports* = object ## Complete anchors still require later package/dependency/capacity admission.
    data: nil AnchorData
  LookupDemandData = ref object ## Exact recent certificate and immutable context bind all missing requirements.
    recent: RecentAnchoredReports
    context: AncestorContext
    missing: int
    oldest: HeaderSlot
  ReportLookupDemand* = object ## Read-only discovery plan is separate from completed lookup certification.
    data: nil LookupDemandData
  ReportAnchorResult*[T] = object ## Success-only payload extraction uses the supported checked-build contract.
    case status: ReportAnchorError
    of None:
      completed: T
    else:
      discard # Neither a default nor a refusal exposes progress.

func error*[T](outcome: ReportAnchorResult[T]): ReportAnchorError =
  ## Inspect a reason without permitting external retagging.
  outcome.status

func value*[T](outcome: ReportAnchorResult[T]): T {.inline,
    requires: outcome.status == ReportAnchorError.None.} =
  ## Extract only a completely selected success.
  outcome.completed

proc recentPolicy*(owner: RecentAnchoredReports): ReportAnchorResult[PolicyCheckedReports] =
  ## Retain the exact policy certificate whose reports were checked.
  let data = owner.data
  if data == nil:
    return ReportAnchorResult[PolicyCheckedReports](status: ReportAnchorError.Uninitialized) # No default batch.
  ReportAnchorResult[PolicyCheckedReports](status: ReportAnchorError.None, completed: data.policy)

proc anchorHistory*(owner: RecentAnchoredReports): ReportAnchorResult[HistorySnapshot] =
  ## Retain corrected history for subsequent package/dependency checks without mutable storage.
  let data = owner.data
  if data == nil:
    return ReportAnchorResult[HistorySnapshot](status: ReportAnchorError.Uninitialized) # No fabricated empty history.
  ReportAnchorResult[HistorySnapshot](status: ReportAnchorError.None, completed: data.history)

proc anchoredRecent*(owner: AnchoredReports): ReportAnchorResult[RecentAnchoredReports] =
  ## Retain the complete prior stage after lookup-anchor certification.
  let data = owner.data
  if data == nil:
    return ReportAnchorResult[RecentAnchoredReports](
        status: ReportAnchorError.Uninitialized) # No disconnected reports.
  ReportAnchorResult[RecentAnchoredReports](status: ReportAnchorError.None, completed: data.recent)

proc checkRecentReportAnchors*(policy: PolicyCheckedReports, correctedHistory: openArray[byte],
    slot: StateTime, config: ReportAnchorConfig): ReportAnchorResult[RecentAnchoredReports] =
  ## Caller supplies the actual beta-dagger after parent-state-root correction, not the appended posterior history.
  ## Decode exactly under current bounds; age subtraction saturates mathematically at genesis without wrapping.
  let credentials = policy.policyCredentials
  if credentials.error != ReportPolicyError.None:
    return ReportAnchorResult[RecentAnchoredReports](
        status: ReportAnchorError.InvalidPolicy) # Require the completed preceding stage.
  if uint64(config.history.cores) < 2 or uint64(config.history.cores) > 341:
    return ReportAnchorResult[RecentAnchoredReports](
        status: ReportAnchorError.InvalidConfig) # No inferred profile.
  let decoded = decodeHistoryState(correctedHistory, config.history)
  if decoded.error == HistoryError.LimitExceeded:
    return ReportAnchorResult[RecentAnchoredReports](
        status: ReportAnchorError.LimitExceeded) # Preserve resource refusals.
  if decoded.error != HistoryError.None:
    return ReportAnchorResult[RecentAnchoredReports](
        status: ReportAnchorError.InvalidHistory) # Never use a partial C(3).
  if decoded.value.consumed != correctedHistory.len:
    return ReportAnchorResult[RecentAnchoredReports](
        status: ReportAnchorError.InvalidHistory) # No suffix fallback.
  let history = decoded.value.snapshot
  let count = historyInfo(history).value.blocks
  # Match all fields on one record, not fields scattered over different historical entries.
  for i in 0..<credentials.value.verifiedGuaranteeCount.value:
    let report = ownedReportInfo(credentials.value.verifiedGuaranteeAt(i).value.report).value.header
    var found = false
    # The history codec already bounds this traversal to at most eight records.
    for j in 0..<count:
      let record = historyBlockAt(history, HistoryBlockIndex(j)).value
      if report.anchor.bytes == array[32, byte](record.header) and
          report.stateRoot.bytes == array[32, byte](record.state) and
          report.accumulationRoot.bytes == array[32, byte](record.superPeak) and
          uint32(report.anchorSlot) == uint32(record.slot):
        found = true # One complete tuple establishes the recent anchor.
        break
    if not found:
      return ReportAnchorResult[RecentAnchoredReports](
          status: ReportAnchorError.InvalidRecentAnchor) # No hash-only acceptance.
    let current = uint64(uint32(slot))
    if current > uint64(config.lookupAge) and
        uint64(uint32(report.lookupSlot)) < current-uint64(config.lookupAge):
      return ReportAnchorResult[RecentAnchoredReports](
          status: ReportAnchorError.LookupTooOld) # Inclusive lower bound, safe near genesis.
  ReportAnchorResult[RecentAnchoredReports](status: ReportAnchorError.None,
    completed: RecentAnchoredReports(data: RecentData(policy: policy, history: history, slot: slot)))

proc checkReportLookupAnchors*(recent: RecentAnchoredReports, parent: OwnedHeader,
    older: openArray[OwnedHeader], config: AncestorConfig): ReportAnchorResult[AnchoredReports] =
  ## Parent is trusted chain context; older headers are supplied newest-first and must link all the way to it.
  ## Both lookup header and its newer child must be in this retained ancestor sequence, never the candidate header.
  let data = recent.data
  if data == nil:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidRecent) # A default cannot bypass the first stage.
  let captured = captureAncestorContext(parent, older, AncestorContextLimits(
    header: config.header, headers: config.headers, maxBytes: config.maxBytes))
  case captured.error
  of AncestorContextError.None: discard # Only a full capture may be retained by the final report certificate.
  of AncestorContextError.LimitExceeded:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.LimitExceeded)
  of AncestorContextError.BrokenAncestry:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.BrokenAncestry)
  of AncestorContextError.BackendFailure:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.BackendFailure)
  else:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidHeader)
  let context = captured.value
  if uint32(context.headerAt(0).value.headerInfo.value.unsigned.slot) >= uint32(data.slot):
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidSlot)
  let credentials = data.policy.policyCredentials.value
  # Every report needs the lookup hash, its own slot and the child-committed posterior root together.
  for i in 0..<credentials.verifiedGuaranteeCount.value:
    let report = ownedReportInfo(credentials.verifiedGuaranteeAt(i).value.report).value.header
    let found = context.findLookupAnchor(HeaderParent(report.lookupAnchor.bytes),
      HeaderSlot(uint32(report.lookupSlot)), PriorStateRoot(report.lookupStateRoot.bytes))
    if found.error == AncestorContextError.WrongLookupState:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.WrongLookupState)
    if found.error != AncestorContextError.None:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.MissingLookupAnchor)
  ReportAnchorResult[AnchoredReports](status: ReportAnchorError.None,
    completed: AnchoredReports(data: AnchorData(recent: recent, context: context)))

proc missingLookups*(demand: ReportLookupDemand): ReportAnchorResult[int] =
  ## Default discovery cannot masquerade as a complete zero-report proof.
  let data = demand.data
  if data == nil: return ReportAnchorResult[int](status: ReportAnchorError.Uninitialized)
  ReportAnchorResult[int](status: ReportAnchorError.None, completed: data.missing)

proc lookupDemandChild*(demand: ReportLookupDemand): ReportAnchorResult[OwnedHeader] =
  ## Missing context starts at the oldest retained child's parent, never at an arbitrary report hash.
  let data = demand.data
  if data == nil: return ReportAnchorResult[OwnedHeader](status: ReportAnchorError.Uninitialized)
  if data.missing == 0:
    return ReportAnchorResult[OwnedHeader](status: ReportAnchorError.MissingLookupAnchor)
  ReportAnchorResult[OwnedHeader](status: ReportAnchorError.None,
    completed: data.context.headerAt(data.context.len - 1).value)

proc lookupDemandMaximum*(demand: ReportLookupDemand, available: ElementLimit): ReportAnchorResult[ElementLimit] =
  ## Strict slot descent bounds potentially useful headers independently of the operator's remaining count.
  let data = demand.data
  if data == nil: return ReportAnchorResult[ElementLimit](status: ReportAnchorError.Uninitialized)
  if data.missing == 0:
    return ReportAnchorResult[ElementLimit](status: ReportAnchorError.None, completed: ElementLimit(0))
  if uint64(available) == 0:
    return ReportAnchorResult[ElementLimit](status: ReportAnchorError.LimitExceeded)
  let child = data.context.headerAt(data.context.len - 1).value.headerInfo.value.unsigned
  let distance = uint64(uint32(child.slot)) - uint64(uint32(data.oldest))
  ReportAnchorResult[ElementLimit](status: ReportAnchorError.None,
    completed: ElementLimit(min(distance, uint64(available))))

proc planReportLookupDemand*(recent: RecentAnchoredReports,
    context: AncestorContext): ReportAnchorResult[ReportLookupDemand] =
  ## Only certified recent/age-valid reports can request older context; no failed-prefix certificate is exposed.
  let data = recent.data
  if data == nil:
    return ReportAnchorResult[ReportLookupDemand](status: ReportAnchorError.InvalidRecent)
  if not context.valid:
    return ReportAnchorResult[ReportLookupDemand](status: ReportAnchorError.InvalidHeader)
  if uint32(context.headerAt(0).value.headerInfo.value.unsigned.slot) >= uint32(data.slot):
    return ReportAnchorResult[ReportLookupDemand](status: ReportAnchorError.InvalidSlot)
  let oldest = uint32(context.headerAt(context.len - 1).value.headerInfo.value.unsigned.slot)
  let credentials = data.policy.policyCredentials.value
  var missing = 0
  var minimum = oldest
  for index in 0..<credentials.verifiedGuaranteeCount.value:
    # Query every report before exposing any demand: a later permanent mismatch refuses the entire plan.
    let report = ownedReportInfo(credentials.verifiedGuaranteeAt(index).value.report).value.header
    let slot = uint32(report.lookupSlot)
    let found = context.findLookupAnchor(HeaderParent(report.lookupAnchor.bytes), HeaderSlot(slot),
      PriorStateRoot(report.lookupStateRoot.bytes))
    if found.error == AncestorContextError.None: continue # Existing complete proof needs no acquisition.
    if found.error == AncestorContextError.WrongLookupState:
      return ReportAnchorResult[ReportLookupDemand](status: ReportAnchorError.WrongLookupState)
    if found.error != AncestorContextError.MissingLookupAnchor or slot >= oldest:
      return ReportAnchorResult[ReportLookupDemand](status: ReportAnchorError.MissingLookupAnchor)
    inc missing # Credential count is already bounded by the retained complete report batch.
    minimum = min(minimum, slot)
  ReportAnchorResult[ReportLookupDemand](status: ReportAnchorError.None,
    completed: ReportLookupDemand(data: LookupDemandData(recent: recent, context: context,
      missing: missing, oldest: HeaderSlot(minimum))))

proc requiresFuzzView*(owner: AnchoredReports): bool =
  ## The immutable certificate retains the supplied-initial-membership domain through publication.
  let data = owner.data
  data != nil and data.fuzzOrigin

proc checkFuzzReportLookupAnchors*(recent: RecentAnchoredReports, parent: OwnedHeader,
    context: FuzzAncestry, config: AncestorConfig): ReportAnchorResult[AnchoredReports] =
  ## Preserve every GP lookup predicate using real child headers; missing initial evidence stays local.
  let data = recent.data
  if data == nil: return ReportAnchorResult[AnchoredReports](
      status: ReportAnchorError.InvalidRecent)
  let admitted = context.validateFuzzParent(parent, FuzzAncestryLimits(header: config.header,
    records: config.headers, bytes: config.maxBytes))
  case admitted
  of FuzzAncestryError.None: discard # Only the exact immutable parent context may complete this batch.
  of FuzzAncestryError.LimitExceeded:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.LimitExceeded)
  of FuzzAncestryError.BackendFailure:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.BackendFailure)
  else:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidHeader)
  if uint32(parent.headerInfo.value.unsigned.slot) >= uint32(data.slot):
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidSlot)
  let credentials = data.policy.policyCredentials.value
  for index in 0..<credentials.verifiedGuaranteeCount.value:
    let report = ownedReportInfo(credentials.verifiedGuaranteeAt(index).value.report).value.header
    let found = context.findFuzzLookup(FuzzHeaderHash(report.lookupAnchor.bytes),
      HeaderSlot(uint32(report.lookupSlot)), PriorStateRoot(report.lookupStateRoot.bytes))
    if found.error == FuzzAncestryError.WrongLookupState:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.WrongLookupState)
    if found.error != FuzzAncestryError.None:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.MissingLookupAnchor)
  ReportAnchorResult[AnchoredReports](status: ReportAnchorError.None,
    completed: AnchoredReports(data: AnchorData(recent: recent, fuzzContext: context,
        fuzzOrigin: true)))
