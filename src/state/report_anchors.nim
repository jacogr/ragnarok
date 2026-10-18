# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex contextual validity: recent tuple and retained
## ancestor/child proof. These immutable read-only stages do not prove consensus ancestry or
## publish C(10).
##
## Exposes recent and lookup-anchor checks and immutable access to their certified
## policy/history context.

import ../codec/[bounded, state_history, state_safrole, header, report_owned]
import ../crypto/primitives
import ./[report_policy, guarantee_credentials]

type
  ## Lookup age is measured in timeslots, independently of the eight recent blocks.
  LookupAge* = distinct uint64
  ## Exact corrected C(3) decoding and explicit chain-specific lookup age.
  ReportAnchorConfig* = object
    history*: HistoryConfig
    lookupAge*: LookupAge
  ## Independent retained-header count, per-header profile and aggregate serialized-byte ceilings.
  AncestorConfig* = object
    header*: HeaderConfig
    headers*: ElementLimit
    maxBytes*: ByteLimit
  ## Failed/default stages contain a reason alone, never a partially validated batch or chain.
  ReportAnchorError* {.pure.} = enum
    Uninitialized, None, InvalidPolicy, InvalidHistory, InvalidConfig, InvalidSlot,
    LimitExceeded, InvalidRecentAnchor, LookupTooOld, InvalidRecent,
    InvalidHeader, BrokenAncestry, MissingLookupAnchor, WrongLookupState, BackendFailure
  ## Acyclic owner retains the exact preceding policy, corrected history and candidate timeslot.
  RecentData = ref object
    policy: PolicyCheckedReports
    history: HistorySnapshot
    slot: StateTime
  ## Recent/age validation is deliberately distinct from a completed ancestor proof.
  RecentAnchoredReports* = object
    data: nil RecentData
  ## Final owner retains each checked full sealed header and the entire previous stage.
  AnchorData = ref object
    recent: RecentAnchoredReports
    headers: seq[OwnedHeader]
  ## Complete anchors still require later package/dependency/capacity admission.
  AnchoredReports* = object
    data: nil AnchorData
  ## Success-only payload extraction uses the supported checked-build contract.
  ReportAnchorResult*[T] = object
    case status: ReportAnchorError
    of None:
      completed: T
    else:
      discard # Neither a default nor a refusal exposes progress.

## Inspect a reason without permitting external retagging.
func error*[T](outcome: ReportAnchorResult[T]): ReportAnchorError = outcome.status
## Extract only a completely selected success.
func value*[T](outcome: ReportAnchorResult[T]): T {.inline,
    requires: outcome.status == ReportAnchorError.None.} = outcome.completed

## Retain the exact policy certificate whose reports were checked.
proc recentPolicy*(owner: RecentAnchoredReports): ReportAnchorResult[PolicyCheckedReports] =
  let data = owner.data
  if data == nil:
    return ReportAnchorResult[PolicyCheckedReports](status: ReportAnchorError.Uninitialized) # No default batch.
  ReportAnchorResult[PolicyCheckedReports](status: ReportAnchorError.None, completed: data.policy)

## Retain corrected history for subsequent package/dependency checks without mutable storage.
proc anchorHistory*(owner: RecentAnchoredReports): ReportAnchorResult[HistorySnapshot] =
  let data = owner.data
  if data == nil:
    return ReportAnchorResult[HistorySnapshot](status: ReportAnchorError.Uninitialized) # No fabricated empty history.
  ReportAnchorResult[HistorySnapshot](status: ReportAnchorError.None, completed: data.history)

## Retain the complete prior stage after lookup-anchor certification.
proc anchoredRecent*(owner: AnchoredReports): ReportAnchorResult[RecentAnchoredReports] =
  let data = owner.data
  if data == nil:
    return ReportAnchorResult[RecentAnchoredReports](
        status: ReportAnchorError.Uninitialized) # No disconnected reports.
  ReportAnchorResult[RecentAnchoredReports](status: ReportAnchorError.None, completed: data.recent)

## Caller supplies the actual beta-dagger after parent-state-root correction, not the appended posterior history.
## Decode exactly under current bounds; age subtraction saturates mathematically at genesis without wrapping.
proc checkRecentReportAnchors*(policy: PolicyCheckedReports, correctedHistory: openArray[byte],
    slot: StateTime, config: ReportAnchorConfig): ReportAnchorResult[RecentAnchoredReports] =
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

## Parent is trusted chain context; older headers are supplied newest-first and must link all the way to it.
## Both lookup header and its newer child must be in this retained ancestor sequence, never the candidate header.
proc checkReportLookupAnchors*(recent: RecentAnchoredReports, parent: OwnedHeader,
    older: openArray[OwnedHeader], config: AncestorConfig): ReportAnchorResult[AnchoredReports] =
  let data = recent.data
  if data == nil:
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidRecent) # A default cannot bypass the first stage.
  if uint64(older.len) >= uint64(config.headers) or older.len == high(int):
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.LimitExceeded) # Account for parent before adding or allocating.
  let count = older.len+1
  if count > high(int) div sizeof(OwnedHeader) or count > high(int) div sizeof(array[32, byte]):
    return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.LimitExceeded) # Bound native descriptor storage before allocation.
  var bytes = 0'u64
  # Validate every owner and aggregate extent before copying or hashing any input.
  for i in 0..<count:
    let owner = if i == 0: parent else: older[i-1] # Parent is always the chain's newest member.
    let info = headerInfo(owner)
    if info.error != HeaderError.None:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidHeader) # No default full headers.
    let size = uint64(info.value.consumed)
    if size > uint64(config.header.maxBytes) or size > uint64(config.maxBytes)-bytes:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.LimitExceeded) # Safe sum invariant bytes <= maxBytes.
    bytes += size
  var headers = newSeq[OwnedHeader](count)
  var hashes = newSeq[array[32, byte]](count)
  # Recapture full sealed bytes under this header profile, and verify a strictly decreasing linked chain.
  for i in 0..<count:
    let owner = if i == 0: parent else: older[i-1] # Keep borrowed inputs stable during capture.
    var wire = newSeq[byte](headerInfo(owner).value.consumed)
    if encodeOwnedHeader(owner, wire).error != HeaderError.None:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidHeader) # No failed serialization is hashed.
    let decoded = decodeHeader(wire, config.header)
    if decoded.error == HeaderError.LimitExceeded:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.LimitExceeded) # Stricter marker/offender budgets apply again.
    if decoded.error != HeaderError.None or decoded.value.consumed != wire.len:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.InvalidHeader) # Full exact header only.
    headers[i] = decoded.value.owner
    let fields = headerInfo(headers[i]).value.unsigned
    let hash = blake2b256(wire)
    if hash.error != CryptoError.None:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.BackendFailure) # Never compare a fabricated digest.
    hashes[i] = array[32, byte](hash.value)
    if i == 0:
      if uint32(fields.slot) >= uint32(data.slot):
        return ReportAnchorResult[AnchoredReports](
            status: ReportAnchorError.InvalidSlot) # Trusted parent still must precede this candidate.
    else:
      let child = headerInfo(headers[i-1]).value.unsigned
      if uint32(fields.slot) >= uint32(child.slot) or array[32, byte](child.parent) != hashes[i]:
        return ReportAnchorResult[AnchoredReports](
            status: ReportAnchorError.BrokenAncestry) # No gaps, forks, duplicates or reordering.
  let credentials = data.policy.policyCredentials.value
  # Every report needs the lookup hash, its own slot and the child-committed posterior root together.
  for i in 0..<credentials.verifiedGuaranteeCount.value:
    let report = ownedReportInfo(credentials.verifiedGuaranteeAt(i).value.report).value.header
    var found = false
    # Index zero has no retained child, so it cannot satisfy this two-header proof.
    for j in 1..<count:
      if hashes[j] == report.lookupAnchor.bytes and
          uint32(headerInfo(headers[j]).value.unsigned.slot) == uint32(report.lookupSlot):
        if array[32, byte](headerInfo(headers[j-1]).value.unsigned.priorState) !=
            report.lookupStateRoot.bytes:
          return ReportAnchorResult[AnchoredReports](
              status: ReportAnchorError.WrongLookupState) # Use child's prior root, not lookup header's own prior root.
        found = true # This exact parent-linked header and child establish the tuple.
        break
    if not found:
      return ReportAnchorResult[AnchoredReports](status: ReportAnchorError.MissingLookupAnchor) # No on-chain-history substitute for retained headers.
  ReportAnchorResult[AnchoredReports](status: ReportAnchorError.None,
    completed: AnchoredReports(data: AnchorData(recent: recent, headers: headers)))
