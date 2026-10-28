# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze deterministic complete-map proof pages on one original logical source; page responses remain partial until independently checked reconstruction succeeds.
import ./full_logical_proof as app_full_logical_proof
import ./logical_proof as app_logical_proof
import ./proof_query as app_proof_query
import ../state/current_logical as state_current_logical
import ../state/proof_plan as state_proof_plan
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
type
  LogicalProofPageIndex* = distinct uint64 ## Page ordinals are neither physical entry indices nor key limits.
  LogicalProofPageLimits* = object ## Each page admits copied input/retained/sort key storage separately from whole-source selector capture.
    keys*: ElementLimit
    bytes*: ByteLimit
  LogicalProofPagesInfo* = object ## Fixed whole-source observations give deterministic coverage without certifying received bytes.
    pages*, keys*, pageKeys*: int
    root*: StateRoot
  LogicalProofPageInfo* = object ## Offsets describe an immutable contiguous range in the original sorted whole-map selector.
    index*: LogicalProofPageIndex
    pages*, offset*, keys*, totalKeys*: int
    root*: StateRoot
  LogicalProofPages* = object ## The admitted original source and key plan cannot be substituted between page captures.
    initialized: bool
    full: FullLogicalProofPlan
    info: LogicalProofPagesInfo
  LogicalProofPage* = object ## Existing managed proof submission receives only this page's original source and immutable selected keys.
    initialized: bool
    source: CurrentLogicalState
    keys: StateProofPlan
    info: LogicalProofPageInfo
  LogicalProofPageError* {.pure.} = enum ## Whole-selector, page-policy and executable-query refusals retain separate meanings.
    Uninitialized, None, InvalidPlan, InvalidIndex, LimitExceeded, FullFailure, PlanFailure, QueryFailure
  LogicalProofPageResult*[T] = object ## No failed page admits a source/key prefix or a replacement cursor.
    case status: LogicalProofPageError
    of None: completed: T
    of FullFailure: fullReason: FullLogicalProofResult[FullLogicalProofPlan]
    of PlanFailure: planReason: ProofPlanError
    of QueryFailure: queryReason: LogicalProofResult
    else: discard # Only successful immutable plans/pages grant subsequent access.
func error*[T](outcome: LogicalProofPageResult[T]): LogicalProofPageError =
  ## Inspect the selected stage without exposing its tagged payload.
  outcome.status
func value*[T](outcome: LogicalProofPageResult[T]): T {.inline, requires: outcome.status ==
    LogicalProofPageError.None.} =
  ## Extract only successful pages, observations or executable queries.
  outcome.completed
func fullFailure*[T](outcome: LogicalProofPageResult[T]): FullLogicalProofResult[
    FullLogicalProofPlan] {.inline, requires: outcome.status ==
    LogicalProofPageError.FullFailure.} =
  ## Preserve original whole-map selector refusal without inventing a partial plan.
  outcome.fullReason
func planError*[T](outcome: LogicalProofPageResult[T]): ProofPlanError {.inline,
    requires: outcome.status == LogicalProofPageError.PlanFailure.} =
  ## Preserve the existing immutable per-page selector capture's refusal.
  outcome.planReason
func queryFailure*[T](outcome: LogicalProofPageResult[T]): LogicalProofResult {.inline,
    requires: outcome.status == LogicalProofPageError.QueryFailure.} =
  ## Preserve original selected-view and nested proof work refusal.
  outcome.queryReason
proc planLogicalProofPages*(source: CurrentLogicalState, fullLimits: FullLogicalProofLimits,
    pageLimits: LogicalProofPageLimits): LogicalProofPageResult[LogicalProofPages] =
  ## Admit the whole immutable selector and worst-case page key copies before any page can be requested; planning performs no cryptography.
  if uint64(pageLimits.keys) == 0:
    return LogicalProofPageResult[LogicalProofPages](
        status: LogicalProofPageError.LimitExceeded) # Zero page width cannot advance a complete traversal.
  let full = planFullLogicalProof(source, fullLimits)
  if full.error != FullLogicalProofError.None:
    return LogicalProofPageResult[LogicalProofPages](status: LogicalProofPageError.FullFailure,
        fullReason: full)
  let info = full.value.fullLogicalProofInfo.value
  let size = min(uint64(info.keys), uint64(pageLimits.keys))
  let slots = min(uint64(pageLimits.bytes), uint64(high(int))) div uint64(sizeof(StateKey))
  if size > slots div 2:
    return LogicalProofPageResult[LogicalProofPages](status: LogicalProofPageError.LimitExceeded)
  if size div 2 > slots-size*2:
    return LogicalProofPageResult[LogicalProofPages](
        status: LogicalProofPageError.LimitExceeded) # Input, captured output and pinned merge-sort scratch fit before multiplication/narrowing.
  let width = int(max(1'u64, size)) # Empty complete maps still have one empty page, whose response authenticates the empty root.
  let count = if info.keys == 0: 1 else: (info.keys-1) div width+1
  LogicalProofPageResult[LogicalProofPages](status: LogicalProofPageError.None,
    completed: LogicalProofPages(initialized: true, full: full.value,
      info: LogicalProofPagesInfo(pages: count, keys: info.keys, pageKeys: width, root: info.root)))
proc logicalProofPagesInfo*(plan: LogicalProofPages): LogicalProofPageResult[
    LogicalProofPagesInfo] =
  ## Return cached deterministic coverage without exposing mutable cursors.
  if not plan.initialized: return LogicalProofPageResult[LogicalProofPagesInfo](
      status: LogicalProofPageError.InvalidPlan)
  LogicalProofPageResult[LogicalProofPagesInfo](status: LogicalProofPageError.None,
      completed: plan.info)
proc logicalProofPageAt*(plan: LogicalProofPages, index: LogicalProofPageIndex): LogicalProofPageResult[
    LogicalProofPage] =
  ## Capture one admitted page in arbitrary caller order without changing the original plan, root or another page.
  if not plan.initialized: return LogicalProofPageResult[LogicalProofPage](
      status: LogicalProofPageError.InvalidPlan)
  if uint64(index) >= uint64(plan.info.pages): return LogicalProofPageResult[LogicalProofPage](
      status: LogicalProofPageError.InvalidIndex)
  let offset = int(uint64(index))*plan.info.pageKeys # Ordinal admission and ceil-divided page count prove this product at most the original native key count.
  let count = min(plan.info.pageKeys, plan.info.keys-offset)
  let original = plan.full.fullLogicalProofKeys.value
  var keys = newSeq[StateKey](count)
  for i in 0..<count:
    keys[i] = original.keyAt(offset+i).value # Every identity is selected from the original immutable sorted range; raw namespaces are never inverted.
  let captured = captureStateProofPlan(keys, ElementLimit(uint64(count)))
  if captured.error != ProofPlanError.None:
    return LogicalProofPageResult[LogicalProofPage](status: LogicalProofPageError.PlanFailure,
        planReason: captured.error)
  LogicalProofPageResult[LogicalProofPage](status: LogicalProofPageError.None,
    completed: LogicalProofPage(initialized: true, source: plan.full.fullLogicalProofSource.value,
      keys: captured.value,
      info: LogicalProofPageInfo(index: index, pages: plan.info.pages, offset: offset, keys: count,
          totalKeys: plan.info.keys, root: plan.info.root)))
proc logicalProofPageInfo*(page: LogicalProofPage): LogicalProofPageResult[LogicalProofPageInfo] =
  ## Retain fixed original-root range observations, never received-response completeness authority.
  if not page.initialized: return LogicalProofPageResult[LogicalProofPageInfo](
      status: LogicalProofPageError.InvalidPlan)
  LogicalProofPageResult[LogicalProofPageInfo](status: LogicalProofPageError.None,
      completed: page.info)
proc logicalProofPageSource*(page: LogicalProofPage): LogicalProofPageResult[CurrentLogicalState] =
  ## Retain the original logical producer for existing managed submission outside native graph leases.
  if not page.initialized: return LogicalProofPageResult[CurrentLogicalState](
      status: LogicalProofPageError.InvalidPlan)
  LogicalProofPageResult[CurrentLogicalState](status: LogicalProofPageError.None,
      completed: page.source)
proc logicalProofPageKeys*(page: LogicalProofPage): LogicalProofPageResult[StateProofPlan] =
  ## Retain the immutable exact page selector for planned response verification and existing workers.
  if not page.initialized: return LogicalProofPageResult[StateProofPlan](
      status: LogicalProofPageError.InvalidPlan)
  LogicalProofPageResult[StateProofPlan](status: LogicalProofPageError.None, completed: page.keys)
proc captureLogicalProofPageQuery*(page: LogicalProofPage,
    limits: LogicalProofLimits): LogicalProofPageResult[ProofQuery] =
  ## Apply independent existing full-map/view/path/wire/hash policies to this page without accepting a substituted source or selector.
  if not page.initialized: return LogicalProofPageResult[ProofQuery](
      status: LogicalProofPageError.InvalidPlan)
  let captured = captureLogicalProofQuery(page.source, page.keys, limits)
  if captured.error != LogicalProofError.None:
    return LogicalProofPageResult[ProofQuery](status: LogicalProofPageError.QueryFailure,
        queryReason: captured)
  LogicalProofPageResult[ProofQuery](status: LogicalProofPageError.None, completed: captured.value)
