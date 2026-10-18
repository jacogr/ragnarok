# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable RPC chain-view boundary: best block, exact block/parent lookup and retained reports.
## The initial adapter owns one configured Genesis snapshot. It supplies neither live import,
## history nor finality. Copies retain acyclic ARC storage; no callback or borrowed owner escapes.

import ./[genesis, reports]
import ../codec/bounded

type
  ## One consistent read view; private storage can only be populated through the genesis adapter.
  ChainView* = object
    snapshot: GenesisResult

## Capture a successful immutable genesis owner; absent/invalid inputs produce an empty view.
func genesisView*(source: GenesisResult): ChainView =
  if source.error == GenesisError.None:
    return ChainView(snapshot: source) # Retain the validated owner, not caller-owned input bytes.
  ChainView(snapshot: unavailableGenesis()) # Failed inputs expose no payload.

## Select the best retained block without implying import, fork choice or finality.
func bestBlock*(view: ChainView): GenesisResult = view.snapshot

## Resolve the exact full-header identity; unknown hashes never fall back to the current head.
func blockAt*(view: ChainView, hash: BlockHash): GenesisResult =
  if view.snapshot.error == GenesisError.None:
    if array[32, byte](view.snapshot.value.blockHash) == array[32, byte](hash):
      return view.snapshot # A successful result retains its own immutable snapshot lifetime.
  unavailableGenesis() # Empty views and unknown blocks have no snapshot.

## Resolve a parent's retained snapshot. The genesis adapter has no parent, even if header bytes name one.
func parentOf*(view: ChainView, hash: BlockHash): GenesisResult =
  unavailableGenesis() # Raw parent bytes alone cannot establish a block descriptor or posterior state.

## Search reports retained by this view under the caller's existing response-byte budget.
proc reportAt*(view: ChainView, hash: WorkReportHash, limit: ByteLimit): ReportReadResult =
  if view.snapshot.error != GenesisError.None:
    return default(ReportReadResult) # The existing result marks default owners uninitialized.
  reports.workReport(view.snapshot.value, hash, limit)
