# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded metadata-only selection names an actual retained reporting context for standalone negative support. It grants no signature, inclusion, execution or report-validity authority; the fixed worker independently qualifies the selected source.
import ./judgment_claim
import ../chain/[genesis, provider, parameters]
import ../codec/disputes

type
  JudgmentSourceAttempt* = object ## The same reporting block can lead to distinct retained execution histories.
    source*, membership*: genesis.BlockHash
  JudgmentSourceError* {.pure.} = enum ## Missing historical role metadata remains unavailable, never a replacement current key table.
    Uninitialized, None, InvalidClaim, InvalidSource, HistoryUnavailable, LimitExceeded
  JudgmentSourceResult* = object ## A default/refusal contains no usable selected identity.
    case status: JudgmentSourceError
    of None:
      selected, membership: genesis.BlockHash
      slot: uint64
    else: discard                # No guessed source survives a history or profile refusal.
func error*(outcome: JudgmentSourceResult): JudgmentSourceError =
  ## Observe the selected reason before extracting actual metadata.
  outcome.status
func value*(outcome: JudgmentSourceResult): genesis.BlockHash {.requires: outcome.status ==
    JudgmentSourceError.None.} =
  ## This copied hash still needs actual worker-side role, signature and full execution-source qualification.
  outcome.selected
func sourceSlot*(outcome: JudgmentSourceResult): uint64 {.requires:
    outcome.status == JudgmentSourceError.None.} =
  ## Retries continue below the original candidate even when a newer head arrives.
  outcome.slot
func membershipSource*(outcome: JudgmentSourceResult): genesis.BlockHash {.requires:
    outcome.status == JudgmentSourceError.None.} =
  ## A zero value means the claim's original verified membership is used.
  outcome.membership
proc eligible(candidate: BlockSnapshotResult, parameters: Parameters,
    guaranteeSlot, rotation: uint64): bool =
  ## Actual current/previous rotation is the maintained guarantee planner's window; availability's five-slot timeout is unrelated.
  if candidate.error != GenesisError.None or candidate.value.slot < guaranteeSlot: return false
  if not parameters.sameParameterProfile(candidate.value.chainParameters): return false
  let sourceRotation = candidate.value.slot div rotation
  let guaranteeRotation = guaranteeSlot div rotation
  sourceRotation >= guaranteeRotation and sourceRotation-guaranteeRotation <= 1
func containsSource(excluded: openArray[JudgmentSourceAttempt], source,
    membership: genesis.BlockHash): bool =
  for previous in excluded:
    if array[32, byte](previous.source) == array[32, byte](source) and
        array[32, byte](previous.membership) == array[32, byte](membership): return true
  false
proc selectJudgmentSourceIn(view: ChainView, claim: SignedJudgmentClaim,
    receipt: BlockSnapshotResult, membership: genesis.BlockHash,
    excluded: openArray[JudgmentSourceAttempt], maximumSlot: uint64): JudgmentSourceResult =
  if excluded.len > 128 or view.retainedCount > 64:
    return JudgmentSourceResult(status: JudgmentSourceError.LimitExceeded)
  if not claim.valid or claim.judgmentRecord.valid:
    return JudgmentSourceResult(status: JudgmentSourceError.InvalidClaim)
  if view.fuzzOnly or receipt.error != GenesisError.None:
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
    if eligible(candidate, parameters, slot, rotation) and candidate.value.slot <= maximumSlot and
        not excluded.containsSource(candidate.value.blockHash, membership):
      return JudgmentSourceResult(status: JudgmentSourceError.None,
          selected: candidate.value.blockHash, membership: membership, slot: candidate.value.slot)
  if not finalSeen and eligible(finalized, parameters, slot, rotation) and
      finalized.value.slot <= maximumSlot and
      not excluded.containsSource(finalized.value.blockHash, membership):
    return JudgmentSourceResult(status: JudgmentSourceError.None,
        selected: finalized.value.blockHash, membership: membership, slot: finalized.value.slot)
  JudgmentSourceResult(status: JudgmentSourceError.HistoryUnavailable)
proc selectJudgmentSource*(view: ChainView, claim: SignedJudgmentClaim,
    excluded: openArray[JudgmentSourceAttempt] = [], maximumSlot = high(
        uint64)): JudgmentSourceResult =
  ## Follow the verified membership and retain the descending retry ceiling across head changes.
  if not claim.valid or claim.judgmentRecord.valid:
    return JudgmentSourceResult(status: JudgmentSourceError.InvalidClaim)
  let receipt = view.blockAt(claim.claimInfo.sourceHead)
  if receipt.error != GenesisError.None or array[32, byte](receipt.value.stateRoot) !=
      array[32, byte](claim.claimInfo.sourceRoot):
    return JudgmentSourceResult(status: JudgmentSourceError.InvalidSource)
  selectJudgmentSourceIn(view, claim, receipt, default(genesis.BlockHash), excluded, maximumSlot)
proc alternateJudgmentSource*(view: ChainView, claim: SignedJudgmentClaim,
    excluded: openArray[JudgmentSourceAttempt]): JudgmentSourceResult =
  ## A retained alternative names a candidate only. The worker must prove the exact same auditor key at the original position.
  if not claim.valid or claim.judgmentRecord.valid:
    return JudgmentSourceResult(status: JudgmentSourceError.InvalidClaim)
  let receipt = view.bestBlock
  if receipt.error != GenesisError.None:
    return JudgmentSourceResult(status: JudgmentSourceError.InvalidSource)
  let period = receipt.value.chainParameters.get(epochPeriod)
  if period == 0: return JudgmentSourceResult(status: JudgmentSourceError.InvalidSource)
  let current = receipt.value.slot div period
  let original = uint64(uint32(claim.claimInfo.epoch))
  if original > current or current-original > 1:
    return JudgmentSourceResult(status: JudgmentSourceError.HistoryUnavailable)
  selectJudgmentSourceIn(view, claim, receipt, receipt.value.blockHash, excluded, high(uint64))
proc selectJudgmentSourceAcross*(primary: ChainView, alternatives: openArray[ChainView],
    claim: SignedJudgmentClaim, excluded: openArray[JudgmentSourceAttempt], maximumSlot: uint64,
    allowPrimary = true, allowAlternates = true): JudgmentSourceResult =
  ## Rotate across trusted histories. Alternate work does not spend the descending primary budget.
  let root = primary.bestBlock
  if root.error != GenesisError.None or alternatives.len > 65 or excluded.len > 128:
    return default(JudgmentSourceResult)
  let selected = if allowPrimary: selectJudgmentSource(primary, claim, excluded, maximumSlot)
    else: default(JudgmentSourceResult)
  if not allowAlternates or (excluded.len == 0 and selected.error == JudgmentSourceError.None):
    return selected
  var lanes = @[-1]
  var start = 0
  if excluded.len > 0 and array[32, byte](excluded[excluded.len-1].membership) ==
      default(array[32, byte]): start = 1
  for index in 0..<alternatives.len:
    let head = alternatives[index].bestBlock
    if head.error != GenesisError.None or array[32, byte](head.value.blockHash) ==
        array[32, byte](root.value.blockHash): continue
    lanes.add(index)
    if excluded.len > 0 and array[32, byte](head.value.blockHash) ==
        array[32, byte](excluded[excluded.len-1].membership):
      start = lanes.len
  for offset in 0..<lanes.len:
    let lane = lanes[(start+offset) mod lanes.len]
    let candidate = if lane < 0: selected else:
      alternateJudgmentSource(alternatives[lane], claim, excluded)
    if candidate.error == JudgmentSourceError.None: return candidate
  selected
