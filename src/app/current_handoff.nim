# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One prepared current update or one unacknowledged result provides bounded producer backpressure without execution.
import ./chain
import ../chain/genesis
import ../rpc/server
import ../state/[store, accumulation_current_update]
type
  CurrentHandoffPhase* {.pure.} = enum ## Finished success/refusal occupies capacity until explicit acknowledgment.
    Idle, Pending, Finished
  CurrentHandoffAdmission* {.pure.} = enum ## Refused admission leaves existing ownership untouched.
    None, Busy, Unavailable, InvalidUpdate, StaleState
  CurrentHandoffError* {.pure.} = enum ## Defaults and refusals carry no fabricated captured child.
    Uninitialized, None, StaleState, RpcRefused
  CurrentHandoffResult* = object ## Only confirmed current installation exposes the exact captured child.
    case status: CurrentHandoffError
    of None: completed: BlockSnapshot
    else: discard # Refusal/default alternatives retain no candidate prefix.
  CurrentAccumulationHandoff* = object ## One private closed slot retains a genuine prepared update or its terminal result.
    case status: CurrentHandoffPhase
    of Pending: update: PreparedCurrentChainUpdate
    of Finished: outcome: CurrentHandoffResult
    else: discard # Idle owns no source, result or implicit queue.
func phase*(handoff: CurrentAccumulationHandoff): CurrentHandoffPhase =
  ## Observe producer capacity without reading or changing the retained candidate.
  handoff.status
func error*(outcome: CurrentHandoffResult): CurrentHandoffError =
  ## Observe only the selected installation status.
  outcome.status
func value*(outcome: CurrentHandoffResult): BlockSnapshot {.inline,
    requires: outcome.status == CurrentHandoffError.None.} =
  ## Retain only an actually installed captured current child.
  outcome.completed
proc enqueue*(handoff: var CurrentAccumulationHandoff, owner: ApplicationChain,
    update: PreparedCurrentChainUpdate): CurrentHandoffAdmission =
  ## Backpressure precedes parent inspection; admission retains immutable handles without hashing or guest work.
  if handoff.status != CurrentHandoffPhase.Idle: return CurrentHandoffAdmission.Busy
  if owner.stateSnapshot.error != StateStoreError.None: return CurrentHandoffAdmission.Unavailable
  if not update.ready: return CurrentHandoffAdmission.InvalidUpdate
  if not owner.canInstallPrepared(update): return CurrentHandoffAdmission.StaleState
  handoff = CurrentAccumulationHandoff(status: CurrentHandoffPhase.Pending, update: update)
  CurrentHandoffAdmission.None
proc pendingUpdate*(handoff: CurrentAccumulationHandoff): PreparedCurrentChainUpdate {.requires:
    handoff.status == CurrentHandoffPhase.Pending.} =
  ## Retain the already prepared immutable candidate, never a writable application or source borrow.
  handoff.update
proc process*(handoff: var CurrentAccumulationHandoff, owner: var ApplicationChain) =
  ## Attempt at most one current update; success and exact-parent refusal both require acknowledgment.
  if handoff.status != CurrentHandoffPhase.Pending: return # Idle and Finished never retry installation.
  let update = handoff.update
  if not owner.canInstallPrepared(update):
    handoff = CurrentAccumulationHandoff(status: CurrentHandoffPhase.Finished,
      outcome: CurrentHandoffResult(status: CurrentHandoffError.StaleState))
    return # A changed parent cannot authorize the queued candidate.
  owner.installPrepared(update)
  handoff = CurrentAccumulationHandoff(status: CurrentHandoffPhase.Finished,
    outcome: CurrentHandoffResult(status: CurrentHandoffError.None,
        completed: update.currentUpdateChild))
proc process*(handoff: var CurrentAccumulationHandoff, owner: var ApplicationChain,
    rpc: var Server, lease: nil RpcChainLease = nil) =
  ## Enabled RPC must join the exact prepared state/history/lease; refusal never falls back to canonical-only installation.
  if handoff.status != CurrentHandoffPhase.Pending: return # Terminal results retain their slot until taken.
  let update = handoff.update
  if not owner.canInstallPrepared(update):
    handoff = CurrentAccumulationHandoff(status: CurrentHandoffPhase.Finished,
      outcome: CurrentHandoffResult(status: CurrentHandoffError.StaleState))
    return # Check canonical ownership separately before RPC admission.
  if not owner.canInstallPrepared(rpc, update, lease):
    handoff = CurrentAccumulationHandoff(status: CurrentHandoffPhase.Finished,
      outcome: CurrentHandoffResult(status: CurrentHandoffError.RpcRefused))
    return # Closed, foreign-history or mismatched lease RPC has no silent fallback.
  owner.installPrepared(rpc, update, lease)
  handoff = CurrentAccumulationHandoff(status: CurrentHandoffPhase.Finished,
    outcome: CurrentHandoffResult(status: CurrentHandoffError.None,
        completed: update.currentUpdateChild))
proc take*(handoff: var CurrentAccumulationHandoff): CurrentHandoffResult {.requires:
    handoff.status == CurrentHandoffPhase.Finished.} =
  ## Transfer exactly one retained result and release producer backpressure.
  result = handoff.outcome
  handoff = default(CurrentAccumulationHandoff)
proc cancel*(handoff: var CurrentAccumulationHandoff): bool =
  ## Only an unattempted update may be dropped; completed results require acknowledgment.
  if handoff.status != CurrentHandoffPhase.Pending: return false
  handoff = default(CurrentAccumulationHandoff)
  true
