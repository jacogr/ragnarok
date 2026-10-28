# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ready-ring evidence retains full report children and owner-bound dependency sets with exact framing.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../support/state_proof_global_report
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
proc main() {.raises.} =
  ## Validate one nonempty ready slot and all independent child/outer resource policies.
  let config = WorkQueueConfig(epochSlots: EpochSlots(2), cores: CoreCount(2),
      perSlot: ElementLimit(2),
    totalItems: ElementLimit(2), perDependencies: ElementLimit(2), totalDependencies: ElementLimit(2),
    reportBytes: ByteLimit(60000), maxBytes: ByteLimit(65536))
  var hash = default(PackageHash)
  hash.bytes[0] = 17
  var rows = newSeq[ReadyRow](2)
  rows[1] = @[ReadyItem(report: globalReport(), dependencies: @[hash])]
  let entry = readyStateEntry(rows, config).value
  let view = globalView(@[entry], [entry.key])
  let owner = view.readGlobalReady(config).value
  let info = owner.readyInfo.value
  assert info.slots == 2 and info.items == 1 and info.dependencies == 1
  assert owner.readySlotCount(WorkQueueSlot(0)).value == 0
  let child = owner.readyItemAt(WorkQueueSlot(1), ReadyItemIndex(0)).value
  assert child.dependencies == 1
  rows = @[]
  assert owner.readyDependencyAt(WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  assert default(ProofView).readGlobalReady(config).error == GlobalProofError.Uninitialized
  assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalReady(config).error ==
      GlobalProofError.MissingWitness
  assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalReady(config).error ==
      GlobalProofError.AbsentValue
  var policy = config
  policy.totalDependencies = ElementLimit(0)
  assert view.readGlobalReady(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.totalItems = ElementLimit(0)
  assert view.readGlobalReady(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.reportBytes = ByteLimit(0)
  assert view.readGlobalReady(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.maxBytes = ByteLimit(entry.value.len-1)
  assert view.readGlobalReady(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.epochSlots = EpochSlots(0)
  assert view.readGlobalReady(policy).error == GlobalProofError.InvalidConfig
  for length in [0, 1, 2, entry.value.len-33, entry.value.len-1]:
    # Slot/count/report/dependency boundaries remain complete-value requirements after authentication.
    var truncated = newSeq[byte](length)
    for i in 0..<length: truncated[i] = entry.value[i]
    assert globalView(@[StateEntry(key: entry.key, value: truncated)], [entry.key]).readGlobalReady(
        config).error == GlobalProofError.InvalidValue
  var suffix = entry.value
  suffix.add(0)
  assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalReady(
      config).error == GlobalProofError.InvalidValue
  echo "state-global-ready-reads: ok"
try:
  main()
except:
  quit(2) # Fixture setup/transport must succeed before the expected native output.
