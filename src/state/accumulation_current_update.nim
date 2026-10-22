# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque current updates stage fallible child capture before durable handoff and guarded installation.
import std/assertions
import ./[store, accumulation_current_chain, accumulation_current_consensus]
import ../codec/bounded
import ../chain/[genesis, provider]

type
  CurrentUpdateData = ref object # Private immutable original/candidate handles and captured child form an acyclic graph.
    parent: StateStoreSnapshot
    prior: ChainView
    state: StateStore
    view: ChainView
    successor: BlockSnapshot
  PreparedCurrentChainUpdate* = object ## Default owners hold no snapshot graph; copies retain one immutable complete preparation.
    data: nil CurrentUpdateData
  CurrentChainPreparationError* {.pure.} = enum ## Failed/default preparation exposes no successful candidate.
    Uninitialized, None, ChainFailure
  CurrentChainPreparationResult* = object ## Only success carries preparation; only a real failed coordinator carries its guarded child reason.
    case status: CurrentChainPreparationError
    of None:
      completed: PreparedCurrentChainUpdate
    of ChainFailure:
      reason: CurrentAccumulationChainResult
    else:
      discard # No successful prefix survives a refused preparation.
func ready*(prepared: PreparedCurrentChainUpdate): bool =
  ## A default owner cannot authorize extraction or installation.
  prepared.data != nil
func error*(outcome: CurrentChainPreparationResult): CurrentChainPreparationError =
  ## Observe only the immutable selected stage.
  outcome.status
func value*(outcome: CurrentChainPreparationResult): PreparedCurrentChainUpdate {.inline,
    requires: outcome.status == CurrentChainPreparationError.None.} =
  ## Only a complete private candidate may leave preparation.
  outcome.completed
func chainFailure*(outcome: CurrentChainPreparationResult): CurrentAccumulationChainResult {.inline,
    requires: outcome.status == CurrentChainPreparationError.ChainFailure.} =
  ## Preserve only the actual failed current coordinator, never its successful prefix.
  outcome.reason
proc prepareCurrentChainUpdate*(state: StateStore, view: ChainView,
    source: PreparedCurrentAccumulationConsensus, headerBytes: ByteLimit): CurrentChainPreparationResult =
  ## Run current prepared-state/capture/append once on private handle copies; retain no mutable caller borrow.
  var working = state
  var history = view
  let applied = applyCurrentAccumulationChain(working, history, source, headerBytes)
  if applied.error != CurrentAccumulationChainError.None:
    return CurrentChainPreparationResult(status: CurrentChainPreparationError.ChainFailure,
      reason: applied) # Failed private stages retain no candidate owner or child.
  CurrentChainPreparationResult(status: CurrentChainPreparationError.None,
    completed: PreparedCurrentChainUpdate(data: CurrentUpdateData(parent: state.snapshot.value,
      prior: view, state: working, view: history, successor: applied.value)))
proc currentUpdateState*(prepared: PreparedCurrentChainUpdate): StateStoreSnapshot {.requires: prepared.data != nil.} =
  ## Retain the exact candidate map for durable export, never a writable target handle.
  let data = prepared.data
  assert data != nil # Stable retained ownership discharges nullable field access after the public guard.
  data.successor.stateSnapshot
proc currentUpdateView*(prepared: PreparedCurrentChainUpdate): ChainView {.requires: prepared.data != nil.} =
  ## Retain complete immutable ordered history, parameters and explicit finality for context encoding.
  let data = prepared.data
  assert data != nil # Capture one stable immutable owner for the nullable proof.
  data.view
proc currentUpdateChild*(prepared: PreparedCurrentChainUpdate): BlockSnapshot {.requires: prepared.data != nil.} =
  ## Retain the exact captured child without recapture or hashing.
  let data = prepared.data
  assert data != nil # The checked public precondition and stable local forbid an absent child owner.
  data.successor
proc canInstallCurrentChainUpdate*(state: StateStore, view: ChainView,
    prepared: PreparedCurrentChainUpdate): bool =
  ## Check exact state ownership and complete ordered history/profile/finality before any durable operation.
  let data = prepared.data
  if data == nil: return false # Default handles carry no retained parent or candidate authority.
  let current = state.snapshot
  current.error == StateStoreError.None and sameStateSnapshot(current.value, data.parent) and
    sameChainView(view, data.prior)
proc installCurrentChainUpdate*(state: var StateStore, view: var ChainView,
    prepared: PreparedCurrentChainUpdate) {.requires: canInstallCurrentChainUpdate(state, view, prepared).} =
  ## Single-threaded stable owners cannot change across preflight/durability/install; replacements perform no hashing or callbacks.
  let data = prepared.data
  assert data != nil # Readiness proves the retained data owner before the sole pair of target assignments.
  state = data.state
  view = data.view
