# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated judgment/offender sets retain canonical ordering and separate result domains.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_disputes as codec_state_disputes
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
let config = DisputeStateConfig(perSet: ElementLimit(3), totalItems: ElementLimit(8),
    maxBytes: ByteLimit(1024))
var a = default(array[32, byte])
var b = default(array[32, byte])
a[0] = 17
b[0] = 18
var source = default(DisputeState)
source.reports[JudgmentSet.Good] = @[DisputeHash(a), DisputeHash(b)]
source.reports[JudgmentSet.Bad] = @[DisputeHash(a)]
source.offenders = @[OffenderKey(b)]
let entry = disputeStateEntry(source, config).value
let view = globalView(@[entry], [entry.key])
let owner = view.readGlobalDisputes(config).value
assert owner.disputeStateInfo.value.reports[JudgmentSet.Good] == 2
assert owner.disputeStateInfo.value.reports[JudgmentSet.Wonky] == 0
assert array[32, byte](owner.judgedReportAt(JudgmentSet.Bad, DisputeStateIndex(0)).value)[0] == 17
assert array[32, byte](owner.stateOffenderAt(DisputeStateIndex(0)).value)[0] == 18
source = default(DisputeState)
assert owner.disputeStateInfo.value.offenders == 1
assert default(ProofView).readGlobalDisputes(config).error == GlobalProofError.Uninitialized
assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalDisputes(config).error ==
    GlobalProofError.MissingWitness
assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalDisputes(config).error ==
    GlobalProofError.AbsentValue
var policy = config
policy.perSet = ElementLimit(1)
assert view.readGlobalDisputes(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.totalItems = ElementLimit(3)
assert view.readGlobalDisputes(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.maxBytes = ByteLimit(entry.value.len-1)
assert view.readGlobalDisputes(policy).error == GlobalProofError.LimitExceeded
for length in 0..<entry.value.len:
  # Every truncated prefix is independently authenticated but still cannot authorize a typed complete set.
  var truncated = newSeq[byte](length)
  for i in 0..<length: truncated[i] = entry.value[i]
  assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
      entry.key]).readGlobalDisputes(config).error == GlobalProofError.InvalidValue
var malformed = entry.value
let duplicate = malformed[1]
malformed[33] = duplicate
assert globalView(@[StateEntry(key: entry.key, value: malformed)], [entry.key]).readGlobalDisputes(
    config).error == GlobalProofError.InvalidValue
var suffix = entry.value
suffix.add(0)
assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalDisputes(
    config).error == GlobalProofError.InvalidValue
echo "state-global-dispute-reads: ok"
