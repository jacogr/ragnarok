# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted history constructors; expected transitions and hash commitments remain separately
## authored.
##
## Exposes bounded history profiles, source constructors and re-exported history/output codec
## domains.

import std/assertions
import ../../src/codec/[state_history, state_outputs, bounded, assurances]
export state_history, state_outputs, bounded, assurances

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
