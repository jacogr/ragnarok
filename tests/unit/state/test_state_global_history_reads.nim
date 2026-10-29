# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated recent blocks/optional peaks retain exact framing and resource/absence distinctions.
import std/[assertions, syncio]
import ../../support/proof_global_helpers
import ../../../src/state/proof/[global as proof_global, view as proof_view]
import ../../../src/codec/[bounded, assurances]
import ../../../src/codec/state/[history as state_history, layout as state_layout,
    safrole as state_safrole, trie as state_trie]
let config = HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
  totalPackages: ElementLimit(4), peaks: ElementLimit(8), maxBytes: ByteLimit(4096))
let source = HistoryState(blocks: @[HistoryBlock(slot: HistorySlot(19), packages: @[])],
  peaks: @[absentHistoryPeak(), presentHistoryPeak(default(HistoryPeakHash))])
let entry = historyStateEntry(source, config).value
let view = globalView(@[entry], [entry.key])
let snapshot = view.readGlobalHistory(config).value
assert snapshot.historyInfo.value.blocks == 1 and snapshot.historyInfo.value.peaks == 2
assert uint32(snapshot.historyBlockAt(HistoryBlockIndex(0)).value.slot) == 19
assert not snapshot.historyPeakAt(HistoryPeakIndex(0)).value.present
assert snapshot.historyPeakAt(HistoryPeakIndex(1)).value.present
assert default(ProofView).readGlobalHistory(config).error == GlobalProofError.Uninitialized
assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalHistory(config).error ==
    GlobalProofError.MissingWitness
assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalHistory(config).error ==
    GlobalProofError.AbsentValue
var policy = config
policy.blocks = ElementLimit(0)
assert view.readGlobalHistory(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.maxBytes = ByteLimit(entry.value.len-1)
assert view.readGlobalHistory(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.cores = CoreCount(0)
assert view.readGlobalHistory(policy).error == GlobalProofError.InvalidConfig
for length in 0..<entry.value.len:
  # Every independently authenticated truncated prefix must fail the exact typed read.
  var truncated = newSeq[byte](length)
  for i in 0..<length: truncated[i] = entry.value[i]
  assert globalView(@[StateEntry(key: entry.key, value: truncated)], [entry.key]).readGlobalHistory(
      config).error == GlobalProofError.InvalidValue
var suffix = entry.value
suffix.add(0)
assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalHistory(
    config).error == GlobalProofError.InvalidValue
echo "state-global-history-reads: ok"
