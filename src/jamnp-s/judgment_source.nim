# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded metadata-only selection names an actual retained reporting context for standalone negative support. It grants no signature, inclusion, execution or report-validity authority; the fixed worker independently qualifies the selected source.
import ./judgment_claim
import ../chain/[genesis, provider, parameters]
import ../codec/disputes

type
  JudgmentSourceError* {.pure.} = enum ## Missing historical role metadata remains unavailable, never a replacement current key table.
    Uninitialized, None, InvalidClaim, InvalidSource, HistoryUnavailable, LimitExceeded
  JudgmentSourceResult* = object ## A default/refusal contains no usable selected identity.
    case status: JudgmentSourceError
    of None: selected: genesis.BlockHash
    else: discard                # No guessed source survives a history or profile refusal.
func error*(outcome: JudgmentSourceResult): JudgmentSourceError =
  ## Observe the selected reason before extracting actual metadata.
  outcome.status
func value*(outcome: JudgmentSourceResult): genesis.BlockHash {.requires: outcome.status ==
    JudgmentSourceError.None.} =
  ## This copied hash still needs actual worker-side role, signature and full execution-source qualification.
  outcome.selected
proc eligible(candidate: BlockSnapshotResult, parameters: Parameters,
    guaranteeSlot, rotation: uint64): bool =
  ## Actual current/previous rotation is the maintained guarantee planner's window; availability's five-slot timeout is unrelated.
  if candidate.error != GenesisError.None or candidate.value.slot < guaranteeSlot: return false
  if not parameters.sameParameterProfile(candidate.value.chainParameters): return false
  let sourceRotation = candidate.value.slot div rotation
  let guaranteeRotation = guaranteeSlot div rotation
  sourceRotation >= guaranteeRotation and sourceRotation-guaranteeRotation <= 1
func containsSource(excluded: openArray[genesis.BlockHash], hash: genesis.BlockHash): bool =
  for previous in excluded:
    if array[32, byte](previous) == array[32, byte](hash): return true
  false
proc selectJudgmentSource*(view: ChainView, claim: SignedJudgmentClaim,
    excluded: openArray[genesis.BlockHash] = []): JudgmentSourceResult =
  ## Inspect at most64 retained fixed metadata rows plus actual separate finality, trying newest known contexts at or after the raw slot. Failure makes no claim about report truth or unsupported unknown history.
  if excluded.len > 64: return JudgmentSourceResult(
      status: JudgmentSourceError.LimitExceeded)
  if not claim.valid or claim.judgmentRecord.valid:
    return JudgmentSourceResult(status: JudgmentSourceError.InvalidClaim)
  if view.fuzzOnly: return JudgmentSourceResult(status: JudgmentSourceError.InvalidSource)
  if view.retainedCount > 64: return JudgmentSourceResult(status: JudgmentSourceError.LimitExceeded)
  let receipt = view.blockAt(claim.claimInfo.sourceHead)
  if receipt.error != GenesisError.None or array[32, byte](receipt.value.stateRoot) != array[32,
      byte](claim.claimInfo.sourceRoot):
    return JudgmentSourceResult(status: JudgmentSourceError.InvalidSource)
  let parameters = receipt.value.chainParameters
  let rotation = parameters.get(rotationPeriod)
  if rotation == 0: return JudgmentSourceResult(status: JudgmentSourceError.InvalidSource)
  let slot = uint64(uint32(claim.judgmentRecord.slot))
  let finalized = view.finalizedBlock
  var finalSeen = false
  for offset in 0..<view.retainedCount:
    # Newest eligible metadata is attempted first; bounded later retries can reach pre-offence historical contexts without replacing any key table.
    let ordinal = view.retainedCount-1-offset
    let candidate = view.retainedBlockAt(RetainedBlockIndex(ordinal))
    if finalized.error == GenesisError.None and candidate.error == GenesisError.None:
      if array[32, byte](finalized.value.blockHash) == array[32, byte](
          candidate.value.blockHash): finalSeen = true
    if eligible(candidate, parameters, slot, rotation) and
        not excluded.containsSource(candidate.value.blockHash):
      return JudgmentSourceResult(status: JudgmentSourceError.None,
          selected: candidate.value.blockHash)
  if not finalSeen and eligible(finalized, parameters, slot, rotation) and
      not excluded.containsSource(finalized.value.blockHash):
    return JudgmentSourceResult(status: JudgmentSourceError.None,
        selected: finalized.value.blockHash)
  JudgmentSourceResult(status: JudgmentSourceError.HistoryUnavailable)
