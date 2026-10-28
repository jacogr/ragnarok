# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Select every serialized key of the original qualified logical successor for existing bounded proof generation and independently checked complete import.
import ./logical_proof as app_logical_proof
import ./proof_query as app_proof_query
import ../state/current_logical as state_current_logical
import ../state/proof_plan as state_proof_plan
import ../state/store as state_store
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
type
  FullLogicalProofLimits* = object ## Complete physical key traversal and input/retained/sort key arrays have independent selector policies.
    keys*: ElementLimit
    bytes*: ByteLimit
  FullLogicalProofInfo* = object ## Whole-source selector coverage describes the original posterior commitment, not caller root trust or response completeness.
    keys*: int
    bytes*: uint64
    root*: StateRoot
  FullLogicalProofPlan* = object ## Original logical provenance and every requested physical identity stay paired and immutable.
    initialized: bool
    source: CurrentLogicalState
    keys: StateProofPlan
    info: FullLogicalProofInfo
  FullLogicalProofError* {.pure.} = enum ## Invalid original source/plan, independent selector policy and existing capture stages remain distinct.
    Uninitialized, None, InvalidLogical, InvalidPlan, LimitExceeded, PlanFailure, QueryFailure
  FullLogicalProofResult*[T] = object ## No failure exposes a selector, original source or executable query prefix.
    case status: FullLogicalProofError
    of None: completed: T
    of PlanFailure: planReason: ProofPlanError
    of QueryFailure: queryReason: LogicalProofResult
    else: discard # Refused whole-map admission cannot masquerade as a successful partial selection.
func error*[T](outcome: FullLogicalProofResult[T]): FullLogicalProofError =
  ## Observe the selected immutable stage without granting its payload.
  outcome.status
func value*[T](outcome: FullLogicalProofResult[T]): T {.inline, requires: outcome.status ==
    FullLogicalProofError.None.} =
  ## Extract only complete original-source selectors, fixed observations or existing executable queries.
  outcome.completed
func planError*[T](outcome: FullLogicalProofResult[T]): ProofPlanError {.inline,
    requires: outcome.status == FullLogicalProofError.PlanFailure.} =
  ## Preserve the original immutable selector capture's genuine refusal.
  outcome.planReason
func queryFailure*[T](outcome: FullLogicalProofResult[T]): LogicalProofResult {.inline,
    requires: outcome.status == FullLogicalProofError.QueryFailure.} =
  ## Preserve selected-view and nested generic proof-query refusal without a default query.
  outcome.queryReason
proc planFullLogicalProof*(source: CurrentLogicalState,
    limits: FullLogicalProofLimits): FullLogicalProofResult[FullLogicalProofPlan] =
  ## Admit cached whole-map counts and all pinned sorting/key storage before traversing any key or allocating selectors.
  let context = source.currentLogicalContext
  if context.error != CurrentLogicalError.None:
    return FullLogicalProofResult[FullLogicalProofPlan](
        status: FullLogicalProofError.InvalidLogical)
  let committed = context.value.state.commitment
  let count = uint64(committed.entries)
  let slots = min(uint64(limits.bytes), uint64(high(int))) div uint64(sizeof(StateKey))
  if count > uint64(limits.keys) or count > slots div 2:
    return FullLogicalProofResult[FullLogicalProofPlan](status: FullLogicalProofError.LimitExceeded)
  if count div 2 > slots-count*2:
    return FullLogicalProofResult[FullLogicalProofPlan](
        status: FullLogicalProofError.LimitExceeded) # Input, retained keys and pinned merge-sort scratch jointly fit before multiplication/narrowing.
  var keys = newSeq[StateKey](committed.entries)
  for i in 0..<keys.len:
    keys[i] = context.value.state.keyAt(StateEntryIndex(
        i)).value # Original complete physical enumeration supplies every key without reconstructing raw namespaces or hashing.
  let captured = captureStateProofPlan(keys, limits.keys)
  if captured.error != ProofPlanError.None:
    return FullLogicalProofResult[FullLogicalProofPlan](status: FullLogicalProofError.PlanFailure,
        planReason: captured.error)
  FullLogicalProofResult[FullLogicalProofPlan](status: FullLogicalProofError.None,
    completed: FullLogicalProofPlan(initialized: true, source: source, keys: captured.value,
      info: FullLogicalProofInfo(keys: committed.entries, bytes: (count*2+count div 2)*uint64(
          sizeof(StateKey)), root: committed.root)))
proc fullLogicalProofInfo*(plan: FullLogicalProofPlan): FullLogicalProofResult[
    FullLogicalProofInfo] =
  ## Copy cached selector work/commitment observations without retaining mutable key arrays.
  if not plan.initialized: return FullLogicalProofResult[FullLogicalProofInfo](
      status: FullLogicalProofError.InvalidPlan)
  FullLogicalProofResult[FullLogicalProofInfo](status: FullLogicalProofError.None,
      completed: plan.info)
proc fullLogicalProofSource*(plan: FullLogicalProofPlan): FullLogicalProofResult[
    CurrentLogicalState] =
  ## Retain only the original source whose complete key set was admitted.
  if not plan.initialized: return FullLogicalProofResult[CurrentLogicalState](
      status: FullLogicalProofError.InvalidPlan)
  FullLogicalProofResult[CurrentLogicalState](status: FullLogicalProofError.None,
      completed: plan.source)
proc fullLogicalProofKeys*(plan: FullLogicalProofPlan): FullLogicalProofResult[StateProofPlan] =
  ## Retain only the admitted immutable complete selector for existing managed proof submission.
  if not plan.initialized: return FullLogicalProofResult[StateProofPlan](
      status: FullLogicalProofError.InvalidPlan)
  FullLogicalProofResult[StateProofPlan](status: FullLogicalProofError.None, completed: plan.keys)
proc captureFullLogicalProofQuery*(plan: FullLogicalProofPlan,
    limits: LogicalProofLimits): FullLogicalProofResult[ProofQuery] =
  ## Existing cached view/map/path/hash/wire admission controls later proof work; no replacement source or key set is accepted.
  if not plan.initialized: return FullLogicalProofResult[ProofQuery](
      status: FullLogicalProofError.InvalidPlan)
  let captured = captureLogicalProofQuery(plan.source, plan.keys, limits)
  if captured.error != LogicalProofError.None:
    return FullLogicalProofResult[ProofQuery](status: FullLogicalProofError.QueryFailure,
        queryReason: captured)
  FullLogicalProofResult[ProofQuery](status: FullLogicalProofError.None, completed: captured.value)
