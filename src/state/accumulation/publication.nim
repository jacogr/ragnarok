# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque complete chain updates stage fallible execution before durable publication and infallible installation.
## Prepared owners retain exact original state/history authority and privately owned successful successors.

import ../store
import ./[chain as accumulation_chain, completion as accumulation_completion,
    finalization as accumulation_finalization]
import ../../chain/[genesis, provider]

type
  PreparedChainUpdate* = object ## Copyable immutable preparation retains no descriptors or mutable external borrows.
    initialized: bool
    parent: StateStoreSnapshot
    prior: ChainView
    state: StateStore
    view: ChainView
    successor: BlockSnapshot
  ChainPreparationError* {.pure.} = enum ## Default/refused preparation exposes no successful candidate.
    Uninitialized, None, ChainFailure
  ChainPreparationResult* = object ## Preserve the actual refused existing coordinator stage without partial success.
    case status: ChainPreparationError
    of None: completed: PreparedChainUpdate
    of ChainFailure: reason: AccumulationChainResult
    else: discard

func ready*(prepared: PreparedChainUpdate): bool =
  ## Defaults cannot authorize candidate reads or publication.
  prepared.initialized

func error*(outcome: ChainPreparationResult): ChainPreparationError =
  ## Observe the preparation stage alone.
  outcome.status

func value*(outcome: ChainPreparationResult): PreparedChainUpdate {.inline,
    requires: outcome.status == ChainPreparationError.None.} =
  ## Only a complete private successor may leave preparation.
  outcome.completed

func chainFailure*(outcome: ChainPreparationResult): AccumulationChainResult {.requires:
    outcome.status == ChainPreparationError.ChainFailure.} =
  ## Preserve only a genuine failed existing adoption, never its successful payload.
  outcome.reason

proc prepareChainUpdate*(state: StateStore, view: ChainView, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): ChainPreparationResult =
  ## Run the unchanged execution/capture/append coordinator on private handle copies exactly once.
  var working = state
  var history = view
  let applied = applyAccumulationChain(working, history, source, limits)
  if applied.error != AccumulationChainError.None:
    return ChainPreparationResult(status: ChainPreparationError.ChainFailure, reason: applied)
  ChainPreparationResult(status: ChainPreparationError.None,
    completed: PreparedChainUpdate(initialized: true, parent: state.snapshot.value, prior: view,
      state: working, view: history, successor: applied.value))

func stateSnapshot*(prepared: PreparedChainUpdate): StateStoreSnapshot {.requires: prepared.initialized.} =
  ## Retain the exact privately prepared map for durable delta export, never a writable target handle.
  prepared.successor.stateSnapshot

func chainView*(prepared: PreparedChainUpdate): ChainView {.requires: prepared.initialized.} =
  ## Retain immutable ordered history and its explicit finalized owner for context encoding.
  prepared.view

func child*(prepared: PreparedChainUpdate): BlockSnapshot {.requires: prepared.initialized.} =
  ## Read the exact successfully captured child without recomposition or header hashing.
  prepared.successor

proc canInstallChainUpdate*(state: StateStore, view: ChainView,
    prepared: PreparedChainUpdate): bool =
  ## Check original owner, complete ordered history, profile and finality before any durable operation.
  if not prepared.initialized: return false
  let current = state.snapshot
  current.error == StateStoreError.None and sameStateSnapshot(current.value, prepared.parent) and
    sameChainView(view, prepared.prior)

proc installChainUpdate*(state: var StateStore, view: var ChainView,
    prepared: PreparedChainUpdate) {.requires: canInstallChainUpdate(state, view, prepared).} =
  ## Single-threaded stable owners cannot change between preflight/durability/installation.
  ## Both replacements retain existing immutable owners; no hashing, composition or callback runs.
  state = prepared.state
  view = prepared.view
