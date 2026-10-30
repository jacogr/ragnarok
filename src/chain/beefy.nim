# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Read the GP 0.8.0 BEEFY commitment from a configured block's retained C(3) history.
## Exposes a bounded read and guarded copied root; no finality or signature is asserted.

import ./genesis
import ../state/store
import ../codec/state/[layout as state_layout, history as state_history]
import ../codec/bounded
export HistorySuperPeak

type
  BeefyReadError* {.pure.} = enum ## Missing, malformed, mismatched and oversized histories contain no readable commitment.
    Uninitialized, None, Unavailable, Malformed, LimitExceeded
  BeefyReadResult* = object ## Success owns a fixed copied root and retains no mutable state or decoder storage.
    case status: BeefyReadError
    of None:
      completed: HistorySuperPeak
    else:
      discard # Failure exposes only its reason.

func error*(value: BeefyReadResult): BeefyReadError =
  ## Inspect the selected outcome without exposing a writable discriminator.
  value.status

func value*(value: BeefyReadResult): HistorySuperPeak {.requires: value.status ==
    BeefyReadError.None.} =
  ## Extract a copied commitment only after selecting success.
  value.completed

proc beefyRoot*(view: Genesis): BeefyReadResult =
  ## Decode the complete bounded chapter and select its newest matching record (GP accoutsignedcommitment).
  ## Missing/empty history is unavailable, not a fabricated zero root. No consensus validation is implied.
  let found = view.lookup(chapterKey(StateChapter(3)))
  if found.error == StateStoreError.Uninitialized:
    return BeefyReadResult(status: BeefyReadError.Uninitialized) # Default owners fail before access.
  if found.error != StateStoreError.None:
    return BeefyReadResult(status: BeefyReadError.Unavailable) # Missing chapter has no commitment.
  if found.value.byteLength > 256 * 1024:
    return BeefyReadResult(status: BeefyReadError.LimitExceeded) # Bound copying and decoder work independently of reply size.
  let wire = found.value.bytes
  let decoded = decodeHistoryState(wire, HistoryConfig(cores: view.cores,
    blocks: ElementLimit(8), perBlock: ElementLimit(341), totalPackages: ElementLimit(2728),
    peaks: ElementLimit(1024), maxBytes: ByteLimit(256 * 1024)))
  if decoded.error != HistoryError.None:
    return BeefyReadResult(status: BeefyReadError.Malformed) # Reject noncanonical/truncated chapters and policy refusal.
  if decoded.value.consumed != wire.len:
    return BeefyReadResult(status: BeefyReadError.Malformed) # A valid prefix alone is insufficient.
  let owner = decoded.value.snapshot
  let info = historyInfo(owner)
  if info.error != HistoryError.None or info.value.blocks == 0:
    return BeefyReadResult(status: BeefyReadError.Unavailable) # Empty genesis history has no last record.
  let latest = historyBlockAt(owner, HistoryBlockIndex(info.value.blocks - 1))
  if latest.error != HistoryError.None:
    return BeefyReadResult(status: BeefyReadError.Malformed) # A complete owner must permit its final index.
  if array[32, byte](latest.value.header) != array[32, byte](view.blockHash) or
      uint32(latest.value.slot) != view.slot:
    return BeefyReadResult(status: BeefyReadError.Malformed) # Never attribute another block's commitment to the requested header.
  BeefyReadResult(status: BeefyReadError.None, completed: latest.value.superPeak)
