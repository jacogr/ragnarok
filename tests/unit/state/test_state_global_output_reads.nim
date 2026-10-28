# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Output log reads preserve sequence order and repeated service identities rather than inventing a dictionary.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_outputs as codec_state_outputs
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
let config = OutputLogConfig(items: ElementLimit(3), maxBytes: ByteLimit(1024))
var marker = default(array[32, byte])
marker[0] = 17
marker[31] = 255
var outputs = @[AccumulationOutput(service: ServiceIndex(high(uint32)),
    commitment: OutputCommitment(marker)),
  AccumulationOutput(service: ServiceIndex(1)), AccumulationOutput(service: ServiceIndex(1))]
let entry = outputLogEntry(outputs, config).value
let view = globalView(@[entry], [entry.key])
let owner = view.readGlobalOutputs(config).value
assert owner.outputLogCount.value == 3
assert uint64(owner.outputLogAt(OutputLogIndex(0)).value.service) == uint64(high(uint32))
assert uint64(owner.outputLogAt(OutputLogIndex(1)).value.service) == 1
assert uint64(owner.outputLogAt(OutputLogIndex(2)).value.service) == 1
outputs = @[]
assert array[32, byte](owner.outputLogAt(OutputLogIndex(0)).value.commitment)[31] == 255
assert default(ProofView).readGlobalOutputs(config).error == GlobalProofError.Uninitialized
assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalOutputs(config).error ==
    GlobalProofError.MissingWitness
assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalOutputs(config).error ==
    GlobalProofError.AbsentValue
var policy = config
policy.items = ElementLimit(2)
assert view.readGlobalOutputs(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.maxBytes = ByteLimit(entry.value.len-1)
assert view.readGlobalOutputs(policy).error == GlobalProofError.LimitExceeded
for length in 0..<entry.value.len:
  # Every truncated count/record prefix remains invalid despite authentic membership.
  var truncated = newSeq[byte](length)
  for i in 0..<length: truncated[i] = entry.value[i]
  assert globalView(@[StateEntry(key: entry.key, value: truncated)], [entry.key]).readGlobalOutputs(
      config).error == GlobalProofError.InvalidValue
var suffix = entry.value
suffix.add(0)
assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalOutputs(
    config).error == GlobalProofError.InvalidValue
echo "state-global-output-reads: ok"
