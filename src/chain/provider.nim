# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable bounded linear RPC history: best block, exact block/parent lookup and retained reports.
## advanceView appends a structurally captured direct child after linkage checks. It does not verify
## execution, signatures, wall-clock validity, fork choice or finality. finalizeView records caller-certified
## finality only; old readers retain their view. At most eight history owners plus one finalized owner.

import ./[genesis, reports]
import ../codec/bounded
from ../state/store import sameStateSnapshot

const MaxRetainedBlocks* = 8 # Local retention policy; no protocol history or finality guarantee.

type
  ChainView* = object ## Private immutable oldest-to-newest snapshots; append allocates a separate sequence container.
    snapshot: seq[BlockSnapshotResult]
    finalized: BlockSnapshotResult # Separate bounded owner; absent until a trusted caller reports finality.
  ViewAdvanceError* {.pure.} = enum ## Default/failure outcomes never contain a replacement view.
    Uninitialized, None, InvalidSnapshot, Duplicate, NotChild, SlotNotIncreasing,
    StateMismatch, ParametersMismatch
  ViewAdvanceResult* = object ## Only success owns a newly selected immutable history; callers retain the prior view on failure.
    case status: ViewAdvanceError
    of None:
      completed: ChainView
    else:
      discard # No partial history escapes a failed append.

  ViewFinalizeError* {.pure.} = enum Uninitialized, None, UnknownBlock,
    Regression ## Finality selection failures carry no replacement view or guessed finalized head.
  ViewFinalizeResult* = object ## Successful selection retains immutable history plus one finalized snapshot.
    case status: ViewFinalizeError
    of None:
      completed: ChainView
    else:
      discard # No partial finality update is observable.

func error*(outcome: ViewFinalizeResult): ViewFinalizeError =
  ## Inspect finality selection without allowing discriminator mutation.
  outcome.status
func value*(outcome: ViewFinalizeResult): ChainView {.requires: outcome.status ==
    ViewFinalizeError.None.} =
  ## Extract a successful immutable replacement only after checking the result.
  outcome.completed

func finalizedBlock*(view: ChainView): BlockSnapshotResult =
  ## Return only explicitly supplied finality; genesis and best-head advances imply none.
  view.finalized

func error*(outcome: ViewAdvanceResult): ViewAdvanceError {.inline.} =
  ## Read the outcome without exposing a mutable discriminator.
  outcome.status
func value*(outcome: ViewAdvanceResult): ChainView {.requires: outcome.status ==
    ViewAdvanceError.None.} =
  ## Extract the replacement view only after selecting success.
  outcome.completed

proc genesisView*(source: GenesisResult): ChainView =
  ## Seed a history from a successful immutable genesis owner; absent/invalid inputs produce an empty view.
  if source.error == GenesisError.None:
    return ChainView(snapshot: @[source]) # Private container retains the structurally checked owner.
  default(ChainView) # Failed inputs expose no payload.

func retainedCount*(view: ChainView): int =
  ## Return the rolling history count, excluding the separately retained finalized owner.
  view.snapshot.len

func bestBlock*(view: ChainView): BlockSnapshotResult =
  ## Select the newest retained block; the caller, not this store, decides which chain is selected.
  if view.snapshot.len == 0:
    return unavailableGenesis() # Default views have no implicit head.
  view.snapshot[^1]

type ChainViewRetentionInfo* = object ## Fixed copied accounting bounds explicit whole-view/index copies, including a separately selected finalized owner.
  history*, owners*: int
  finalized*: bool
  bytes*: uint64
func viewRetentionInfo*(view: ChainView): ChainViewRetentionInfo =
  ## Inspect private slots directly, avoiding temporary copies of each snapshot's key/service indexes.
  var bytes = uint64(sizeof(ChainView)) + uint64(view.snapshot.len) * uint64(sizeof(BlockSnapshotResult))
  for index in 0..<view.snapshot.len:
    bytes += blockSnapshotRetention(view.snapshot[
        index]).indexBytes # At most eight original 16384-entry indexes bound all additions.
  let finalized = view.finalized.error == GenesisError.None
  if finalized:
    bytes += blockSnapshotRetention(view.finalized).indexBytes # The fixed finalized wrapper is already charged by sizeof(ChainView).
  ChainViewRetentionInfo(history: view.snapshot.len, owners: view.snapshot.len + (
      if finalized: 1 else: 0), finalized: finalized, bytes: bytes)
func bestBlockContext*(view: ChainView): BlockSnapshotContext {.requires: view.snapshot.len > 0.} =
  ## Return fixed original head facts and shared immutable handles without copying any private indexes.
  blockSnapshotContext(view.snapshot[^1])

func blockAt*(view: ChainView, hash: BlockHash): BlockSnapshotResult =
  ## Resolve an exact full-header identity in at most nine comparisons, including the finalized owner.
  for saved in view.snapshot:
    if array[32, byte](saved.value.blockHash) == array[32, byte](hash):
      return saved # Successful results retain their own immutable snapshot lifetime.
  if view.finalized.error == GenesisError.None:
    if array[32, byte](view.finalized.value.blockHash) == array[32, byte](hash):
      return view.finalized # Keep finalized-state queries available after history-window eviction.
  unavailableGenesis() # Other evicted blocks are unavailable.

func parentOf*(view: ChainView, hash: BlockHash): BlockSnapshotResult =
  ## Return a parent only when both child and its exact parent are retained in this view.
  let child = view.blockAt(hash)
  if child.error != GenesisError.None:
    return unavailableGenesis() # A historical parent cannot be inferred for an unknown child.
  view.blockAt(child.value.parentHash)

## Compare exact retained block state and complete parameters, without hashing or copying map payloads.
func sameRetainedBlock(left, right: BlockSnapshot): bool =
  array[32, byte](left.blockHash) == array[32, byte](right.blockHash) and
    sameStateSnapshot(left.stateSnapshot, right.stateSnapshot) and left.sameParameters(right)

func sameChainView*(left, right: ChainView): bool =
  ## Require initialized identical ordered history and explicit finality; equal best roots alone do not match.
  if left.snapshot.len == 0 or left.snapshot.len != right.snapshot.len:
    return false # Defaults and different retained windows cannot authorize shared publication.
  for index in 0..<left.snapshot.len:
    if not sameRetainedBlock(left.snapshot[index].value, right.snapshot[index].value):
      return false # Every retained block keeps its exact state version and chain profile.
  if left.finalized.error != right.finalized.error:
    return false # Missing and explicitly selected finality are distinct states.
  if left.finalized.error == GenesisError.None:
    if not sameRetainedBlock(left.finalized.value, right.finalized.value):
      return false # Matching rolling history cannot silently overwrite a different finality selection.
  true

proc advanceView*(view: ChainView, child: BlockSnapshotResult): ViewAdvanceResult =
  ## Append a structurally checked direct child; preserve old views and evict only the oldest on success.
  ## The caller must supply execution-validated state before using this as a live node chain source.
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return ViewAdvanceResult(status: ViewAdvanceError.Uninitialized) # Explicit seeding is required.
  if child.error != GenesisError.None:
    return ViewAdvanceResult(status: ViewAdvanceError.InvalidSnapshot) # Never inspect failure payloads.
  let next = child.value
  if view.blockAt(next.blockHash).error == GenesisError.None:
    return ViewAdvanceResult(status: ViewAdvanceError.Duplicate) # A header identity cannot overwrite retained state.
  if array[32, byte](next.parentHash) != array[32, byte](head.value.blockHash):
    return ViewAdvanceResult(status: ViewAdvanceError.NotChild) # No reorg or fork selection is performed.
  if next.slot <= head.value.slot:
    return ViewAdvanceResult(status: ViewAdvanceError.SlotNotIncreasing) # Gaps are valid; equal/decreasing slots are not.
  if array[32, byte](next.priorStateRoot) != array[32, byte](head.value.stateRoot):
    return ViewAdvanceResult(status: ViewAdvanceError.StateMismatch) # Header prior root names the parent's posterior map.
  if not next.sameParameters(head.value):
    return ViewAdvanceResult(status: ViewAdvanceError.ParametersMismatch) # Keep RPC startup parameters coherent across history.
  let first = if view.snapshot.len == MaxRetainedBlocks: 1 else: 0 # Retain the newest bounded suffix.
  var saved = newSeq[BlockSnapshotResult](view.snapshot.len - first + 1)
  for index in first..<view.snapshot.len:
    saved[index - first] = view.snapshot[index] # Copy owner handles into a fresh private container.
  saved[saved.len - 1] = child
  ViewAdvanceResult(status: ViewAdvanceError.None, completed: ChainView(snapshot: saved,
      finalized: view.finalized))

proc reportAt*(view: ChainView, hash: WorkReportHash, limit: ByteLimit): ReportReadResult =
  ## Search only the selected head's retained reports under the existing byte budget.
  ## Block history does not widen report searches into an archive or multiply decoder work per request.
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return default(ReportReadResult) # The existing result marks default owners uninitialized.
  reports.workReport(head.value, hash, limit)


proc finalizeView*(view: ChainView, hash: BlockHash): ViewFinalizeResult =
  ## Select a caller-certified finalized block on this retained linear chain; no consensus proof is checked.
  ## Reject unknown hashes and regressions; repeated selection is idempotent. Immutable old views survive.
  if view.bestBlock.error != GenesisError.None:
    return ViewFinalizeResult(status: ViewFinalizeError.Uninitialized) # Explicit chain seeding is required.
  let selected = view.blockAt(hash)
  if selected.error != GenesisError.None:
    return ViewFinalizeResult(status: ViewFinalizeError.UnknownBlock) # Never infer finality for an unknown or evicted ancestor.
  if view.finalized.error == GenesisError.None:
    if selected.value.slot < view.finalized.value.slot:
      return ViewFinalizeResult(status: ViewFinalizeError.Regression) # The linear history already proves increasing slots.
  ViewFinalizeResult(status: ViewFinalizeError.None,
    completed: ChainView(snapshot: view.snapshot, finalized: selected))

type RetainedBlockIndex* = distinct int ## Oldest-to-newest ordinal belongs only to this immutable retained view.
func retainedBlockAt*(view: ChainView, index: RetainedBlockIndex): BlockSnapshotResult =
  ## Copy an owner-bound retained block; defaults and out-of-window ordinals remain unavailable.
  if int(index) < 0 or int(index) >= view.snapshot.len: return unavailableGenesis()
  view.snapshot[int(index)]
proc restoreLocalChainView*(history: openArray[BlockSnapshotResult],
    finalized = unavailableGenesis()): ViewAdvanceResult =
  ## Restore a previously validated local bounded history; this is not a consensus or import verifier.
  ## Evicted finality is an explicit trusted local anchor: its ancestry predates the retained window.
  if history.len == 0 or history.len > MaxRetainedBlocks:
    return ViewAdvanceResult(status: ViewAdvanceError.InvalidSnapshot)
  for saved in history:
    if saved.error != GenesisError.None:
      return ViewAdvanceResult(status: ViewAdvanceError.InvalidSnapshot) # No default/failed slot can become a historical block.
  var restored = genesisView(history[0])
  for index in 1..<history.len:
    let advanced = restored.advanceView(history[index])
    if advanced.error != ViewAdvanceError.None:
      return ViewAdvanceResult(status: advanced.error) # Reuse exact direct-child, prior-root, slot and full-profile checks.
    restored = advanced.value
  if finalized.error == GenesisError.None:
    let known = restored.blockAt(finalized.value.blockHash)
    if known.error == GenesisError.None:
      if not sameRetainedBlock(known.value, finalized.value):
        return ViewAdvanceResult(status: ViewAdvanceError.InvalidSnapshot) # Equal header/root cannot substitute another map owner.
      restored.finalized = known # Preserve the identical restored in-window snapshot owner.
    else:
      if not finalized.value.sameParameters(history[0].value):
        return ViewAdvanceResult(status: ViewAdvanceError.ParametersMismatch)
      if finalized.value.slot >= history[0].value.slot:
        return ViewAdvanceResult(status: ViewAdvanceError.SlotNotIncreasing) # An unknown finality anchor must predate the retained suffix.
      restored.finalized = finalized # Caller-local durable authority supplies the evicted ancestry binding.
  elif finalized.error != GenesisError.Unavailable:
    return ViewAdvanceResult(status: ViewAdvanceError.InvalidSnapshot) # A failed finality result is not an explicit absent selection.
  ViewAdvanceResult(status: ViewAdvanceError.None, completed: restored)
