# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application-owned complete state and selected history, independent of optional RPC transport lifetime.
## Explicit RPC publication joins only matching histories; copies form independent immutable-parent branches.

import ../chain/[genesis, provider, parameters]
import ../state/[store, accumulation_chain, accumulation_finalization, accumulation_completion,
  accumulation_publication, accumulation_current_consensus, accumulation_current_update,
  accumulation_storage_history, service_identity_history, request_identity_history]
import ../codec/bounded
import ../state/parent_profile
import ../rpc/server as rpc_server
from ../rpc/protocol import configuredParameters, configuredGenesis

type
  ApplicationChain* = object ## Private independently updateable handle pair; copies share only immutable prior state/history.
    state: StateStore
    view: ChainView
  ApplicationChainError* {.pure.} = enum ## Failed/default results retain only the selected reason, never partial application owners.
    Uninitialized, None, MissingHead, StateFailure, ChainFailure, RpcFailure, ParametersFailure,
      GenesisFailure, DurabilityRequired, DurabilityFailure
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
    of ParametersFailure:
      parametersReason: ParameterError
    of GenesisFailure:
      genesisReason: GenesisError
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

func parametersError*[T](outcome: ApplicationChainResult[T]): ParameterError {.inline,
    requires: outcome.status == ApplicationChainError.ParametersFailure.} =
  ## Preserve only the actual failed bounded parameter decode, with no partial configuration tuple.
  outcome.parametersReason
func genesisFailure*[T](outcome: ApplicationChainResult[T]): GenesisError {.inline,
    requires: outcome.status == ApplicationChainError.GenesisFailure.} =
  ## Distinguish an absent pair from an invalid configured genesis/policy without exposing candidate maps.
  outcome.genesisReason

func chainView*(chain: ApplicationChain): ChainView =
  ## Retain an immutable request/history view; default owners retain an explicitly uninitialized view.
  chain.view
proc captureParentProfile*(chain: ApplicationChain,
    limits: ParentProfileLimits): ParentProfileResult[SelectedParentProfile] =
  ## Borrow the original private view directly so profile admission precedes its whole-view/index copy.
  parent_profile.captureParentProfile(chain.view, limits)
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

proc initApplicationChain*(text: string, limits: StateStoreLimits): ApplicationChainResult[
    ApplicationChain] =
  ## Initialize from bounded chainspec text with a mandatory caller policy; commit once and share the exact seed map.
  ## Structural capture does not establish completeness, consensus validity, light-state verification or persistence.
  let parameters = configuredParameters(text)
  if not parameters.ok:
    return ApplicationChainResult[ApplicationChain](status: ApplicationChainError.ParametersFailure,
      parametersReason: parameters.error) # Bad/default parameters cannot authorize any genesis hash work.
  let genesis = configuredGenesis(text, parameters.value, limits)
  if genesis.error != GenesisError.None:
    return ApplicationChainResult[ApplicationChain](status: ApplicationChainError.GenesisFailure,
      genesisReason: genesis.error) # Missing/invalid pairs and refused policy/backend work expose no partial owner.
  initApplicationChain(genesisView(genesis)) # Fork the captured version without a second trie commitment or policy replacement.

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

proc prepareAccumulation*(chain: ApplicationChain, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): ChainPreparationResult =
  ## Stage existing fallible adoption privately while retaining the exact original application authority.
  prepareChainUpdate(chain.state, chain.view, source, limits)
proc canInstallPrepared*(chain: ApplicationChain, prepared: PreparedChainUpdate): bool =
  ## Check original state and entire history/finality before starting any durable publication.
  canInstallChainUpdate(chain.state, chain.view, prepared)
proc installPrepared*(chain: var ApplicationChain, prepared: PreparedChainUpdate) {.requires:
    canInstallPrepared(chain, prepared).} =
  ## Assignment-only canonical replacement occurs after confirmed durability and under host exclusion.
  installChainUpdate(chain.state, chain.view, prepared)
proc canInstallPrepared*(chain: ApplicationChain, rpc: rpc_server.Server,
    prepared: PreparedChainUpdate, lease: nil rpc_server.RpcChainLease = nil): bool =
  ## Enabled RPC must retain the exact same ordered history and the caller's optional exclusive lease.
  rpc.canInstallPreparedAccumulation(chain.state, chain.view, prepared, lease)
proc installPrepared*(chain: var ApplicationChain, rpc: var rpc_server.Server,
    prepared: PreparedChainUpdate, lease: nil rpc_server.RpcChainLease = nil) {.requires:
      canInstallPrepared(chain, rpc, prepared, lease).} =
  ## Join canonical and RPC owners before subscriber work; no execution/capture/hash is repeated.
  rpc.installPreparedAccumulation(chain.state, chain.view, prepared, lease)

proc prepareAccumulation*(chain: ApplicationChain, source: PreparedCurrentAccumulationConsensus,
    headerBytes: ByteLimit, storageLimits = default(StorageHistoryLimits),
    requestLimits = default(RequestIdentityHistoryLimits),
    serviceLimits = default(ServiceIdentityHistoryLimits)): CurrentChainPreparationResult =
  ## Stage the genuine current composed child privately, preserving the exact canonical parent/view and complete parameter tuple.
  prepareCurrentChainUpdate(chain.state, chain.view, source, headerBytes, storageLimits,
      requestLimits, serviceLimits)
proc canInstallPrepared*(chain: ApplicationChain, prepared: PreparedCurrentChainUpdate): bool =
  ## Current candidates retain exact original state and complete history/finality before durability begins.
  canInstallCurrentChainUpdate(chain.state, chain.view, prepared)
proc installPrepared*(chain: var ApplicationChain, prepared: PreparedCurrentChainUpdate) {.requires:
    canInstallPrepared(chain, prepared).} =
  ## Assignment-only current installation follows confirmed durability under stable single-threaded ownership.
  installCurrentChainUpdate(chain.state, chain.view, prepared)
proc canInstallPrepared*(chain: ApplicationChain, rpc: rpc_server.Server,
    prepared: PreparedCurrentChainUpdate, lease: nil rpc_server.RpcChainLease = nil): bool =
  ## Enabled RPC joins only exact current canonical history and the caller's matching optional exclusive lease.
  rpc.canInstallPreparedAccumulation(chain.state, chain.view, prepared, lease)
proc installPrepared*(chain: var ApplicationChain, rpc: var rpc_server.Server,
    prepared: PreparedCurrentChainUpdate, lease: nil rpc_server.RpcChainLease = nil) {.requires:
      canInstallPrepared(chain, rpc, prepared, lease).} =
  ## Replace current canonical/RPC handles before subscriber work without execution, capture or hashing.
  rpc.installPreparedAccumulation(chain.state, chain.view, prepared, lease)
proc installedPrepared*(chain: ApplicationChain, prepared: PreparedCurrentChainUpdate): ApplicationChainResult[
    BlockSnapshot] {.requires:
    prepared.ready and sameStateSnapshot(chain.stateSnapshot.value, prepared.currentUpdateState) and
    sameChainView(chain.chainView, prepared.currentUpdateView).} =
  ## Acknowledge only the exact already installed current child; this performs no mutation or capture.
  ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.None,
    completed: prepared.currentUpdateChild)

proc durabilityRequired*(): ApplicationChainResult[BlockSnapshot] =
  ## Disk consumers use the asynchronous handoff; synchronous application calls cannot bypass persistence.
  ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.DurabilityRequired)
proc durabilityFailure*(): ApplicationChainResult[BlockSnapshot] =
  ## The service retains the exact disk stage/IO outcome separately; this completion grants no child.
  ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.DurabilityFailure)
proc preparationRefusal*(failure: ChainPreparationResult): ApplicationChainResult[
    BlockSnapshot] {.requires:
    failure.error == ChainPreparationError.ChainFailure.} =
  ## Preserve the original composition/capture refusal without synthesizing a partial child.
  ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.ChainFailure,
      chainReason: failure.chainFailure)
proc installedPrepared*(chain: ApplicationChain, prepared: PreparedChainUpdate): ApplicationChainResult[
    BlockSnapshot] {.requires:
    prepared.ready and sameStateSnapshot(chain.stateSnapshot.value, prepared.stateSnapshot) and
    sameChainView(chain.chainView, prepared.chainView).} =
  ## Acknowledge only the exact already installed successor; this result performs no mutation or capture.
  ApplicationChainResult[BlockSnapshot](status: ApplicationChainError.None,
      completed: prepared.child)
