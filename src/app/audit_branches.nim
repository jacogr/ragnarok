# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Side-branch sources retain only fully prepared children of independently trusted views.
import ../chain/[genesis, provider]
import ../codec/bounded
import ../state/store
import ../state/accumulation/current/update

type
  AuditBranchLimits* = object ## Aggregate reservation covers each full retained map and its owner descriptors.
    branches*: ElementLimit
    bytes*: ByteLimit
  AuditBranchError* {.pure.} = enum ## No refusal changes the selected chain or installs partial audit history.
    Uninitialized, None, UnknownParent, SourceMismatch, Duplicate, LimitExceeded, Exhausted
  AuditBranchCandidate* = object ## Fixed scheduling identity survives independent removal of older rows.
    serial*: uint64
    hash*: genesis.BlockHash
  AuditBranchRow = object ## An immutable independently linked view owns its actual child and original ancestors.
    candidate: AuditBranchCandidate
    charge: uint64
    view: ChainView
  AuditBranches* = object ## Stable Services storage is mutated only outside the shared worker lease.
    limits: AuditBranchLimits
    used, next: uint64
    rows: seq[AuditBranchRow]

func valid*(limits: AuditBranchLimits): bool =
  ## Bounded policy leaves omission inactive and caps whole-map reservations independently.
  uint64(limits.branches) in 1'u64..64'u64 and uint64(limits.bytes) in 1'u64..16'u64*1024*1024*1024
proc configure*(owner: var AuditBranches, limits: AuditBranchLimits): bool =
  ## Retention cannot be reconfigured over an existing branch authority.
  if owner.limits.valid or not limits.valid: return false
  owner.limits = limits
  true
proc at*(owner: AuditBranches, hash: genesis.BlockHash): ChainView =
  ## Resolve only an independently admitted exact branch child.
  for row in owner.rows:
    if array[32, byte](row.candidate.hash) == array[32, byte](hash): return row.view
  default(ChainView)
func len*(owner: AuditBranches): int =
  ## Fixed count exposes neither map nor mutable queue storage.
  owner.rows.len
func nextAfter*(owner: AuditBranches, after: uint64): AuditBranchCandidate =
  ## Stable monotonic positions permit compaction without skipping an unprocessed sibling.
  for row in owner.rows:
    if row.candidate.serial > after: return row.candidate
  default(AuditBranchCandidate)
proc clear*(owner: var AuditBranches) =
  ## Joined Services teardown retires every independently retained view.
  owner = default(AuditBranches)
proc parentView*(owner: AuditBranches, selected: ChainView, parent: genesis.BlockHash): ChainView =
  ## An older selected parent must still be on the finalized branch; a side parent must still name actual installed finality.
  let canonical = selected.retainedPrefix(parent)
  if canonical.error == ViewAdvanceError.None: return canonical.value
  let branch = owner.at(parent)
  if branch.bestBlock.error != GenesisError.None: return default(ChainView)
  let finalized = selected.finalizedBlock
  if finalized.error == GenesisError.None:
    let trusted = branch.blockAt(finalized.value.blockHash)
    if trusted.error != GenesisError.None or not sameStateSnapshot(trusted.value.stateSnapshot,
        finalized.value.stateSnapshot):
      return default(ChainView)
    let anchored = branch.finalizeView(finalized.value.blockHash)
    if anchored.error != ViewFinalizeError.None: return default(ChainView)
    return anchored.value
  branch
proc retire*(owner: var AuditBranches, selected: ChainView) =
  ## Reclaim branches already selected or that diverge before independently installed finality.
  let finalized = selected.finalizedBlock
  if finalized.error != GenesisError.None: return
  var kept = 0
  for index in 0..<owner.rows.len:
    # Full parent ownership is kept for every surviving row and its stable serial is never changed.
    let hash = owner.rows[index].candidate.hash
    let anchor = owner.rows[index].view.blockAt(finalized.value.blockHash)
    if selected.blockAt(hash).error == GenesisError.None or anchor.error != GenesisError.None or
        not sameStateSnapshot(anchor.value.stateSnapshot, finalized.value.stateSnapshot):
      owner.used -= owner.rows[index].charge
    else:
      if kept != index: owner.rows[kept] = move(owner.rows[index])
      inc kept
  owner.rows.setLen(kept)
proc liveViews*(owner: AuditBranches, selected: ChainView): seq[ChainView] =
  ## Capture only independently retained alternatives that still descend from actual installed finality.
  result = @[]
  for row in owner.rows:
    # Use the same current finality boundary as local source resolution.
    let branch = owner.parentView(selected, row.candidate.hash)
    if branch.bestBlock.error == GenesisError.None: result.add(branch)
proc chargeBlock(selected: BlockSnapshot, used: var uint64, limit: uint64): bool =
  ## Reserve the inherited map ceiling, committed entries/nodes and the exact optional block body.
  let state = selected.stateSnapshot
  let counts = state.commitment
  let values = state.retainedValueLimit
  let body = if selected.hasBlockBody: uint64(selected.blockBodyLength) else: 0'u64
  if values > limit-used: return false
  used += values
  if body > limit-used: return false
  used += body
  if counts.nodes > (limit-used) div 256: return false
  used += counts.nodes*256
  if uint64(counts.entries) > (limit-used) div 128: return false
  used += uint64(counts.entries)*128
  true
proc reservation(view: ChainView, limit: uint64): uint64 =
  ## Conservatively count each retained owner including separately pinned finality and header-only anchors.
  result = view.viewRetentionInfo.bytes
  if result > limit: return high(uint64)
  let headerCount = uint64(view.retainedCount)+uint64(view.validationHeaderCount)+1
  if headerCount > (limit-result) div 262144'u64: return high(uint64)
  result += headerCount*262144'u64
  for index in 0..<view.retainedCount:
    # Count maps independently even when immutable subtrees share storage.
    let selected = view.retainedBlockAt(RetainedBlockIndex(index)).value
    if not chargeBlock(selected, result, limit): return high(uint64)
  let finalized = view.finalizedBlock
  if finalized.error == GenesisError.None and not chargeBlock(finalized.value, result, limit):
    return high(uint64)
proc retain*(owner: var AuditBranches, selected: ChainView,
    prepared: PreparedCurrentChainUpdate): AuditBranchError =
  ## Compare the certificate's entire prior view against independently retained state before granting side-branch authority.
  if not owner.limits.valid or not prepared.ready: return AuditBranchError.Uninitialized
  let prior = prepared.currentUpdatePriorView
  let parent = prior.bestBlock
  if parent.error != GenesisError.None: return AuditBranchError.UnknownParent
  let expected = owner.parentView(selected, parent.value.blockHash)
  if expected.bestBlock.error != GenesisError.None: return AuditBranchError.UnknownParent
  if not sameChainView(expected, prior): return AuditBranchError.SourceMismatch
  let hash = prepared.currentUpdateChildContext.hash
  if selected.blockAt(hash).error == GenesisError.None or owner.at(hash).bestBlock.error ==
      GenesisError.None:
    return AuditBranchError.Duplicate
  if uint64(owner.rows.len) >= uint64(owner.limits.branches): return AuditBranchError.LimitExceeded
  if owner.next == high(uint64): return AuditBranchError.Exhausted
  let view = prepared.currentUpdateView
  let charge = reservation(view, uint64(owner.limits.bytes)-owner.used)
  if charge == high(uint64): return AuditBranchError.LimitExceeded
  inc owner.next
  owner.rows.add(AuditBranchRow(candidate: AuditBranchCandidate(serial: owner.next, hash: hash),
      view: view, charge: charge))
  owner.used += charge
  AuditBranchError.None
