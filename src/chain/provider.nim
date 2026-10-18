# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable bounded linear RPC history: best block, exact block/parent lookup and retained reports.
## advanceView appends a structurally captured direct child after linkage checks. It does not verify
## execution, signatures, wall-clock validity, fork choice or finality. Old readers retain their view.

import ./[genesis, reports]
import ../codec/bounded

const MaxRetainedBlocks* = 8 # Local retention policy; no protocol history or finality guarantee.

type
  ## Private oldest-to-newest snapshots; every construction allocates a separate sequence container.
  ChainView* = object
    snapshot: seq[BlockSnapshotResult]
  ## Default/failure outcomes never contain a replacement view.
  ViewAdvanceError* {.pure.} = enum
    Uninitialized, None, InvalidSnapshot, Duplicate, NotChild, SlotNotIncreasing,
    StateMismatch, ParametersMismatch
  ## Only success owns a newly selected immutable history; callers retain the prior view on failure.
  ViewAdvanceResult* = object
    case status: ViewAdvanceError
    of None:
      completed: ChainView
    else:
      discard # No partial history escapes a failed append.

## Read the outcome without exposing a mutable discriminator.
func error*(outcome: ViewAdvanceResult): ViewAdvanceError {.inline.} = outcome.status
## Extract the replacement view only after selecting success.
func value*(outcome: ViewAdvanceResult): ChainView {.requires: outcome.status ==
    ViewAdvanceError.None.} = outcome.completed

## Seed a history from a successful immutable genesis owner; absent/invalid inputs produce an empty view.
proc genesisView*(source: GenesisResult): ChainView =
  if source.error == GenesisError.None:
    return ChainView(snapshot: @[source]) # Private container retains the structurally checked owner.
  default(ChainView) # Failed inputs expose no payload.

## Return the bounded number of snapshots owned by this specific view.
func retainedCount*(view: ChainView): int = view.snapshot.len

## Select the newest retained block; the caller, not this store, decides which chain is selected.
func bestBlock*(view: ChainView): BlockSnapshotResult =
  if view.snapshot.len == 0:
    return unavailableGenesis() # Default views have no implicit head.
  view.snapshot[^1]

## Resolve the exact full-header identity in at most eight comparisons, never falling back to the head.
func blockAt*(view: ChainView, hash: BlockHash): BlockSnapshotResult =
  for saved in view.snapshot:
    if array[32, byte](saved.value.blockHash) == array[32, byte](hash):
      return saved # Successful results retain their own immutable snapshot lifetime.
  unavailableGenesis() # Empty views, unknown hashes and evicted blocks have no snapshot here.

## Return a parent only when both child and its exact parent are retained in this view.
func parentOf*(view: ChainView, hash: BlockHash): BlockSnapshotResult =
  let child = view.blockAt(hash)
  if child.error != GenesisError.None:
    return unavailableGenesis() # A historical parent cannot be inferred for an unknown child.
  view.blockAt(child.value.parentHash)

## Append a structurally checked direct child; preserve old views and evict only the oldest on success.
## The caller must supply execution-validated state before using this as a live node chain source.
proc advanceView*(view: ChainView, child: BlockSnapshotResult): ViewAdvanceResult =
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
  ViewAdvanceResult(status: ViewAdvanceError.None, completed: ChainView(snapshot: saved))

## Search only the selected head's retained reports under the existing byte budget.
## Block history does not widen report searches into an archive or multiply decoder work per request.
proc reportAt*(view: ChainView, hash: WorkReportHash, limit: ByteLimit): ReportReadResult =
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return default(ReportReadResult) # The existing result marks default owners uninitialized.
  reports.workReport(head.value, hash, limit)
