# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Staging/active/previous roster evidence retains its namespace and opaque fixed record order.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
let config = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
    maxBytes: ByteLimit(3000))
for chapter in [ValidatorChapter.Staging, ValidatorChapter.Active, ValidatorChapter.Previous]:
  # Each roster is independent evidence even when every encoded record happens to match.
  var records = newSeq[StateValidator](6)
  records[5] = nullValidator()
  let entry = validatorEntry(chapter, records, config).value
  let view = globalView(@[entry], [entry.key])
  let owner = view.readGlobalValidators(chapter, config).value
  assert owner.validatorCount.value == 6
  assert array[32, byte](owner.validatorAt(StateValidatorIndex(5)).value.ed25519)[0] == 2
  records[5] = default(StateValidator)
  assert array[32, byte](owner.validatorAt(StateValidatorIndex(5)).value.ed25519)[0] == 2
  assert default(ProofView).readGlobalValidators(chapter, config).error ==
      GlobalProofError.Uninitialized
  assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalValidators(chapter,
      config).error == GlobalProofError.MissingWitness
  assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalValidators(chapter,
      config).error == GlobalProofError.AbsentValue
  let other = if chapter == ValidatorChapter.Active: ValidatorChapter.Previous else: ValidatorChapter.Active
  assert view.readGlobalValidators(other, config).error == GlobalProofError.MissingWitness
  var policy = config
  policy.validators = ElementLimit(5)
  assert view.readGlobalValidators(chapter, policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.maxBytes = ByteLimit(entry.value.len-1)
  assert view.readGlobalValidators(chapter, policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.cores = CoreCount(0)
  assert view.readGlobalValidators(chapter, policy).error == GlobalProofError.InvalidConfig
  for length in [0, 1, 32, 336, entry.value.len-1]:
    # Canonical count, first record and final record extents all require a complete chapter.
    var truncated = newSeq[byte](length)
    for i in 0..<length: truncated[i] = entry.value[i]
    assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
        entry.key]).readGlobalValidators(chapter, config).error == GlobalProofError.InvalidValue
  var suffix = entry.value
  suffix.add(0)
  assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalValidators(
      chapter, config).error == GlobalProofError.InvalidValue
echo "state-global-validator-reads: ok"
