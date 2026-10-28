# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted history constructors; expected transitions and hash commitments remain separately
## authored.
##
## Exposes bounded history profiles, source constructors and re-exported history/output codec
## domains.

import std/assertions
import ../../src/codec/state_history as codec_state_history
import ../../src/codec/state_outputs as codec_state_outputs
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
export codec_state_history, codec_state_outputs, codec_bounded, codec_assurances

proc historyConfig*(cores = 2): HistoryConfig =
  ## Explicit tiny/full profile and finite resource ceilings, not inferred from wire bytes.
  HistoryConfig(cores: CoreCount(uint64(cores)), blocks: ElementLimit(8), perBlock: ElementLimit(
      uint64(cores)),
    totalPackages: ElementLimit(uint64(cores)*8), peaks: ElementLimit(128), maxBytes: ByteLimit(1000000))

proc historyHash*(number: byte): array[32, byte] =
  ## Easily distinguished fixed hashes make field identity and ordering checks readable.
  result = default(array[32, byte])
  result[0] = number

proc historyOwner*(source: HistoryState, cores = 2): HistorySnapshot =
  ## Snapshot capture uses only the existing codec and exact consumption checks.
  let entry = historyStateEntry(source, historyConfig(cores))
  assert entry.error == HistoryError.None
  let parsed = decodeHistoryState(entry.value.value, historyConfig(cores))
  assert parsed.error == HistoryError.None and parsed.value.consumed == entry.value.value.len
  parsed.value.snapshot
