# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One immutable finalized candidate or one unacknowledged adoption result, with explicit producer backpressure.
## Dispatch attempts once; success and refusal are both retained until taken. This module performs no execution.

import ./chain
import ../chain/genesis
import ../rpc/server
import ../state/store
import ../state/accumulation/[finalization as accumulation_finalization,
    completion as accumulation_completion, publication as accumulation_publication]

type
  AccumulationHandoffStage* {.pure.} = enum ## Default Idle owns no candidate; Finished requires explicit acknowledgement.
    Idle, Pending, Publishing, Finished
  AccumulationEnqueueError* {.pure.} = enum ## Failed admission retains no candidate and leaves the existing slot unchanged.
    None, Busy, Unavailable, InvalidSource, StaleState
  AccumulationHandoff* = object ## Private closed alternatives prevent source/result forgery or unbounded queued ownership.
    case status: AccumulationHandoffStage
    of Pending:
      source: PreparedFinalAccumulation
      limits: AccumulationCompositionLimits
    of Finished:
      completion: ApplicationChainResult[BlockSnapshot]
    else:
      discard # Idle has neither candidate nor completed owner.

func stage*(handoff: AccumulationHandoff): AccumulationHandoffStage =
  ## Observe readiness without extracting private candidate storage or consuming results.
  handoff.status

proc enqueue*(handoff: var AccumulationHandoff, chain: ApplicationChain,
    source: PreparedFinalAccumulation, limits: AccumulationCompositionLimits): AccumulationEnqueueError =
  ## Retain one exact-parent certified source without hashing, mutating canonical state or replacing another job/result.
  if handoff.status != AccumulationHandoffStage.Idle:
    return AccumulationEnqueueError.Busy # Completed refusal/success still requires producer acknowledgement.
  let current = chain.stateSnapshot
  if current.error != StateStoreError.None:
    return AccumulationEnqueueError.Unavailable # Default/legacy/closed canonical ownership cannot authorize work.
  let parent = source.finalAccumulationParent
  if parent.error != AccumulationFinalizationError.None:
    return AccumulationEnqueueError.InvalidSource # A default certificate exposes no parent or candidate state.
  if not sameStateSnapshot(current.value, parent.value):
    return AccumulationEnqueueError.StaleState # Equal roots and separately reconstructed parents confer no authority.
  handoff = AccumulationHandoff(status: AccumulationHandoffStage.Pending, source: source,
      limits: limits)
  AccumulationEnqueueError.None

proc process*(handoff: var AccumulationHandoff, chain: var ApplicationChain) =
  ## Attempt at most one candidate through existing RPC-independent adoption and retain its exact outcome.
  if handoff.status != AccumulationHandoffStage.Pending: return # Idle/Finished turns never retry or hash.
  let applied = chain.applyAccumulation(handoff.source, handoff.limits)
  handoff = AccumulationHandoff(status: AccumulationHandoffStage.Finished, completion: applied)

proc process*(handoff: var AccumulationHandoff, chain: var ApplicationChain, rpc: var Server) =
  ## Explicit enabled publication retains listener/stale-view refusal without falling back to independent adoption.
  if handoff.status != AccumulationHandoffStage.Pending: return # One attempt survives until explicit acknowledgement.
  let applied = chain.applyAccumulation(rpc, handoff.source, handoff.limits)
  handoff = AccumulationHandoff(status: AccumulationHandoffStage.Finished, completion: applied)

proc take*(handoff: var AccumulationHandoff): ApplicationChainResult[BlockSnapshot] {.requires:
    handoff.status == AccumulationHandoffStage.Finished.} =
  ## Transfer the immutable success/failure outcome and clear backpressure; never substitute a default completion.
  result = handoff.completion
  handoff = default(AccumulationHandoff)

proc cancel*(handoff: var AccumulationHandoff): bool =
  ## Drop only an unattempted candidate; an unacknowledged completion cannot be silently discarded.
  if handoff.status != AccumulationHandoffStage.Pending: return false
  handoff = default(AccumulationHandoff)
  true

proc preparePending*(handoff: AccumulationHandoff,
    chain: ApplicationChain): ChainPreparationResult {.requires:
    handoff.status == AccumulationHandoffStage.Pending.} =
  ## Stage the opaque update before granting any native durable-publication lease.
  chain.prepareAccumulation(handoff.source, handoff.limits)

proc markPublishing*(handoff: var AccumulationHandoff) {.requires:
    handoff.status == AccumulationHandoffStage.Pending.} =
  ## Retire source aliases before native IO begins; the service owns the opaque publication until receipt collection.
  handoff = AccumulationHandoff(status: AccumulationHandoffStage.Publishing)

proc completePublication*(handoff: var AccumulationHandoff,
    outcome: ApplicationChainResult[BlockSnapshot]) {.requires:
    handoff.status in [AccumulationHandoffStage.Pending, AccumulationHandoffStage.Publishing].} =
  ## Retain one exact host outcome until the original producer acknowledges it, with no retry or adoption here.
  handoff = AccumulationHandoff(status: AccumulationHandoffStage.Finished, completion: outcome)
