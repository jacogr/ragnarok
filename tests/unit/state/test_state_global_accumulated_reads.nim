# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Accumulated package sets retain slot/ordinal identity and reject authenticated noncanonical ordering.
import std/[assertions, syncio]
import ../../support/proof_global_helpers
import ../../../src/state/[proof_global, proof_view]
import ../../../src/codec/[bounded, assurances, state_workqueues, state_layout, state_safrole, state_trie]
let config = WorkQueueConfig(epochSlots: EpochSlots(2), cores: CoreCount(2), perSlot: ElementLimit(2),
  totalItems: ElementLimit(2), perDependencies: ElementLimit(2), totalDependencies: ElementLimit(2),
  reportBytes: ByteLimit(60000), maxBytes: ByteLimit(65536))
var a = default(PackageHash)
var b = default(PackageHash)
a.bytes[0] = 17
b.bytes[0] = 18
var rows = @[newSeq[PackageHash](0), @[a, b]]
let entry = accumulatedStateEntry(rows, config).value
let view = globalView(@[entry], [entry.key])
let owner = view.readGlobalAccumulated(config).value
assert owner.accumulatedInfo.value.slots == 2 and owner.accumulatedInfo.value.items == 2
assert owner.accumulatedSlotCount(WorkQueueSlot(0)).value == 0
assert owner.accumulatedHashAt(WorkQueueSlot(1), WorkQueueHashIndex(1)).value.bytes[0] == 18
rows = @[]
assert owner.accumulatedHashAt(WorkQueueSlot(1), WorkQueueHashIndex(0)).value.bytes[0] == 17
assert default(ProofView).readGlobalAccumulated(config).error == GlobalProofError.Uninitialized
assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalAccumulated(config).error ==
    GlobalProofError.MissingWitness
assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalAccumulated(config).error ==
    GlobalProofError.AbsentValue
assert view.readGlobalReady(config).error == GlobalProofError.MissingWitness
var policy = config
policy.totalItems = ElementLimit(1)
assert view.readGlobalAccumulated(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.perSlot = ElementLimit(1)
assert view.readGlobalAccumulated(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.maxBytes = ByteLimit(entry.value.len-1)
assert view.readGlobalAccumulated(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.epochSlots = EpochSlots(0)
assert view.readGlobalAccumulated(policy).error == GlobalProofError.InvalidConfig
for length in 0..<entry.value.len:
  # Every authenticated truncated prefix still lacks a complete canonical ring value.
  var truncated = newSeq[byte](length)
  for i in 0..<length: truncated[i] = entry.value[i]
  assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
      entry.key]).readGlobalAccumulated(config).error == GlobalProofError.InvalidValue
var malformed = entry.value
let duplicate = malformed[2]
malformed[34] = duplicate
assert globalView(@[StateEntry(key: entry.key, value: malformed)], [
    entry.key]).readGlobalAccumulated(config).error == GlobalProofError.InvalidValue
var suffix = entry.value
suffix.add(0)
assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalAccumulated(
    config).error == GlobalProofError.InvalidValue
echo "state-global-accumulated-reads: ok"
