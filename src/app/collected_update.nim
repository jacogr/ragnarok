# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One exact canonical admission gate for genuine current preparation collection consumers.
import ./[chain, preparation_worker, current_block_input, candidate]
import ../state/accumulation_current_update
type
  CollectedUpdateError* {.pure.} = enum ## Receipt lifecycle and genuine preparation failure remain distinct from stale canonical provenance.
    Uninitialized, None, NoCompletion, Cancelled, WrongOperation, PreparationFailure, StaleUpdate
  CollectedUpdateResult* = object ## Only an actual current completion still installable on this original chain grants its prepared update.
    case status: CollectedUpdateError
    of None: completed: PreparedCurrentChainUpdate
    of PreparationFailure: preparationReason: CurrentBlockInputResult
    else: discard # Defaults, cancellation and stale receipts grant no source prefix.
func error*(outcome: CollectedUpdateResult): CollectedUpdateError =
  ## Observe the selected immutable stage without granting its payload.
  outcome.status
func value*(outcome: CollectedUpdateResult): PreparedCurrentChainUpdate {.inline,
    requires: outcome.status == CollectedUpdateError.None.} =
  ## Retain the actual authenticated update after exact physical/full-view admission.
  outcome.completed
func preparationFailure*(outcome: CollectedUpdateResult): CurrentBlockInputResult {.inline,
    requires: outcome.status == CollectedUpdateError.PreparationFailure.} =
  ## Preserve the original failed receiver and its typed nested cause or ancestor demand.
  outcome.preparationReason
proc captureCollectedUpdate*(chain: ApplicationChain,
    completion: PreparationCompletion): CollectedUpdateResult =
  ## Caller keeps the canonical host gate open; non-current receipts refuse before current extraction or canonical inspection.
  case completion.kind
  of PreparationCompletionKind.Uninitialized:
    return CollectedUpdateResult(status: CollectedUpdateError.NoCompletion)
  of PreparationCompletionKind.Cancelled:
    return CollectedUpdateResult(status: CollectedUpdateError.Cancelled)
  of PreparationCompletionKind.Completed:
    return CollectedUpdateResult(status: CollectedUpdateError.WrongOperation)
  of PreparationCompletionKind.CurrentCompleted:
    let prepared = completion.currentValue
    if prepared.error != CurrentBlockInputError.None:
      return CollectedUpdateResult(status: CollectedUpdateError.PreparationFailure,
          preparationReason: prepared)
    if not chain.canInstallPrepared(prepared.value):
      return CollectedUpdateResult(status: CollectedUpdateError.StaleUpdate)
    return CollectedUpdateResult(status: CollectedUpdateError.None, completed: prepared.value)
