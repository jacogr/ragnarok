# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application-owned complete state and selected history, independent of optional RPC transport lifetime.
## Explicit RPC publication joins only matching histories; copies form independent immutable-parent branches.

import ../chain/[genesis, provider]
import ../state/[store, accumulation_chain, accumulation_finalization, accumulation_completion]
import ../rpc/server as rpc_server

type
  ApplicationChain* = object ## Private independently updateable handle pair; copies share only immutable prior state/history.
    state: StateStore
    view: ChainView
  ApplicationChainError* {.pure.} = enum ## Failed/default results retain only the selected reason, never partial application owners.
    Uninitialized, None, MissingHead, StateFailure, ChainFailure, RpcFailure
  ApplicationChainResult*[T] = object ## Guard constructor/application success separately from actual failed child stages.
    case status: ApplicationChainError
    of None:
      completed: T
    of StateFailure:
      stateReason: StateStoreError
    of ChainFailure:
      chainReason: AccumulationChainResult
    of RpcFailure:
      rpcReason: rpc_server.RpcAccumulationResult
    else:
      discard # Defaults and absent histories contain no usable state, chain or child.

func error*[T](outcome: ApplicationChainResult[T]): ApplicationChainError =
  ## Read status without exposing private result tags.
  outcome.status
func value*[T](outcome: ApplicationChainResult[T]): T {.inline,
    requires: outcome.status == ApplicationChainError.None.} =
  ## Extract only a fully initialized application owner or successfully installed child.
  outcome.completed
func stateError*[T](outcome: ApplicationChainResult[T]): StateStoreError {.inline,
    requires: outcome.status == ApplicationChainError.StateFailure.} =
  ## Inspect only an actual failed seed fork.
  outcome.stateReason
func chainFailure*[T](outcome: ApplicationChainResult[T]): AccumulationChainResult {.inline,
    requires: outcome.status == ApplicationChainError.ChainFailure.} =
  ## Preserve the actual failed RPC-independent adoption and its selected nested causes.
  outcome.chainReason
func rpcFailure*[T](outcome: ApplicationChainResult[T]): rpc_server.RpcAccumulationResult {.inline,
    requires: outcome.status == ApplicationChainError.RpcFailure.} =
  ## Preserve only a failed enabled-listener publication, including stale-view and lifecycle refusal.
  outcome.rpcReason

func chainView*(chain: ApplicationChain): ChainView =
  ## Retain an immutable request/history view; default owners retain an explicitly uninitialized view.
  chain.view
proc stateSnapshot*(chain: ApplicationChain): StateStoreResult[StateStoreSnapshot] =
  ## Retain the canonical complete-map version; default owners return the store's precise initialization error.
  chain.state.snapshot

proc initApplicationChain*(view: ChainView): ApplicationChainResult[ApplicationChain] =
  ## Fork the selected head's exact complete map with inherited policy; never rebuild or infer a writable empty map.
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return ApplicationChainResult[ApplicationChain](
        status: ApplicationChainError.MissingHead) # Explicit selection is mandatory.
  let state = forkStateStore(head.value.stateSnapshot)
  if state.error != StateStoreError.None:
    return ApplicationChainResult[ApplicationChain](status: ApplicationChainError.StateFailure,
      stateReason: state.error) # No policy widening or partial owner escapes a refused fork.
  ApplicationChainResult[ApplicationChain](status: ApplicationChainError.None,
    completed: ApplicationChain(state: state.value, view: view))

proc applyAccumulation*(chain: var ApplicationChain, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): ApplicationChainResult[BlockSnapshot] =
  ## Adopt without a listener when RPC is disabled; the same state-owned coordinator remains authoritative.
  let applied = applyAccumulationChain(chain.state, chain.view, source, limits)
  if applied.error != AccumulationChainError.None:
    return ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.ChainFailure,
      chainReason: applied) # Failure preserves the entire private canonical pair.
  ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.None,
      completed: applied.value)

proc applyAccumulation*(chain: var ApplicationChain, rpc: var rpc_server.Server,
    source: PreparedFinalAccumulation, limits: AccumulationCompositionLimits): ApplicationChainResult[
        BlockSnapshot] =
  ## Adopt canonical state, application history and matching RPC history before any subscriber work.
  let published = rpc_server.publishAccumulation(rpc, chain.state, chain.view, source, limits)
  if published.error != rpc_server.RpcAccumulationError.None:
    return ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.RpcFailure,
      rpcReason: published) # Explicit enabled publication cannot silently degrade to independent adoption.
  ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.None,
      completed: published.value)
