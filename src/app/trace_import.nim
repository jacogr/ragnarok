# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare real current-profile STF imports against the actual selected application chain.
## Advertised pre/post maps are comparison inputs, never sources of Parameters or installable state.
import ./chain as app_chain
import ./candidate as app_candidate
import ../codec/header as codec_header
import ../state/trace_step as state_trace_step
import ../state/trace_state as state_trace_state
import ../state/store as state_store
import ../state/accumulation_current_update as state_accumulation_current_update

type
  TraceImportError* {.pure.} = enum ## A refused trace cannot expose a prepared prefix or a fabricated successor.
    Uninitialized, None, InvalidTrace, MissingParent, PreStateMismatch, CandidateFailure,
      PostStateMismatch, InvalidObservation, ObservationMismatch
  TraceImportResult* = object ## Only exact input/execution/output agreement returns the genuine chain-bound prepared update.
    case status: TraceImportError
    of None: completed: PreparedCurrentChainUpdate
    of CandidateFailure: candidateReason: CurrentCandidateResult
    else: discard # Plain map/default refusals contain no producer certificate or update.

func error*(outcome: TraceImportResult): TraceImportError =
  ## Observe the immutable selected stage without authorizing extraction.
  outcome.status
func value*(outcome: TraceImportResult): PreparedCurrentChainUpdate {.inline,
    requires: outcome.status == TraceImportError.None.} =
  ## Return only a genuine current candidate whose entire advertised successor matched.
  outcome.completed
func candidateFailure*(outcome: TraceImportResult): CurrentCandidateResult {.inline,
    requires: outcome.status == TraceImportError.CandidateFailure.} =
  ## Preserve the actual failed admission/execution stage without a usable prepared prefix.
  outcome.candidateReason

proc sameMapping(left, right: StateStoreSnapshot): bool =
  ## Compare every sorted key/value, including present-empty entries; a matching root alone grants no map equality.
  let a = left.commitment
  let b = right.commitment
  if a.entries != b.entries or array[32, byte](a.root) != array[32, byte](b.root): return false
  for index in 0..<a.entries:
    let first = left.keyAt(StateEntryIndex(index)).value
    let second = right.keyAt(StateEntryIndex(index)).value
    if array[31, byte](first) != array[31, byte](second): return false
    if left.lookup(first).value.bytes != right.lookup(
        second).value.bytes: return false # Exact keys and values prevent a correctly recommitted different map from substituting for the selected source.
  true

proc prepareTraceImport*(chain: ApplicationChain, step: TraceStep,
    ancestors: openArray[OwnedHeader], limits: CurrentCandidateLimits): TraceImportResult =
  ## Borrow the actual chain and ancestry, run ordinary authenticated STF preparation, and return success only after complete map comparison; never install.
  if step.traceStepBytes.error != TraceStepError.None:
    return TraceImportResult(status: TraceImportError.InvalidTrace)
  let selected = chain.stateSnapshot
  if selected.error != StateStoreError.None:
    return TraceImportResult(status: TraceImportError.MissingParent)
  let before = step.tracePreState.value.traceStateSnapshot.value
  if not sameMapping(selected.value, before):
    return TraceImportResult(status: TraceImportError.PreStateMismatch) # Untrusted trace roots cannot select a different parent or replace configured Parameters.
  let prepared = prepareCurrentCandidate(chain, step.traceBlock.value, ancestors, limits)
  if prepared.error != CurrentCandidateError.None:
    return TraceImportResult(status: TraceImportError.CandidateFailure, candidateReason: prepared)
  let after = step.tracePostState.value.traceStateSnapshot.value
  if not sameMapping(prepared.value.currentUpdateState, after):
    return TraceImportResult(status: TraceImportError.PostStateMismatch) # Retire the actual prepared candidate without exposing it when the advertised complete successor differs.
  TraceImportResult(status: TraceImportError.None, completed: prepared.value)


proc prepareTraceObservation*(chain: ApplicationChain, expected: TraceStep,
    observed: TraceState, ancestors: openArray[OwnedHeader],
    limits: CurrentCandidateLimits): TraceImportResult =
  ## Verify the independent golden transition first, then require every external observed key/value to equal the genuine result before exposing a prepared update.
  if observed.traceStateInfo.error != TraceStateError.None:
    return TraceImportResult(status: TraceImportError.InvalidObservation)
  let prepared = prepareTraceImport(chain, expected, ancestors, limits)
  if prepared.error != TraceImportError.None:
    return prepared # An external observation cannot replace a rejected expected block, parent or independently calculated successor.
  if not sameMapping(prepared.value.currentUpdateState, observed.traceStateSnapshot.value):
    return TraceImportResult(status: TraceImportError.ObservationMismatch)
  prepared
