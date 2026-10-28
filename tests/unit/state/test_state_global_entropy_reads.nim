# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every entropy word is retained independently; malformed present evidence never becomes a zero default.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
var words = default(StateEntropy)
for i in 0..<4:
  # Distinct word positions and endpoint bytes expose ordering or truncation mistakes.
  var bytes = default(array[32, byte])
  bytes[0] = byte(i+1)
  bytes[31] = byte(9-i)
  words[i] = StateEntropyWord(bytes)
let entry = entropyEntry(words)
let view = globalView(@[entry], [entry.key])
let decoded = view.readGlobalEntropy(ByteLimit(128)).value
for i in 0..<4:
  assert array[32, byte](decoded[i]) == array[32, byte](words[i]) # Preserve exact fixed fields.
assert view.readGlobalEntropy(ByteLimit(127)).error == GlobalProofError.LimitExceeded
assert default(ProofView).readGlobalEntropy(ByteLimit(128)).error == GlobalProofError.Uninitialized
assert globalView(@[entry], [chapterKey(StateChapter(11))]).readGlobalEntropy(ByteLimit(
    128)).error == GlobalProofError.MissingWitness
assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalEntropy(ByteLimit(
    128)).error == GlobalProofError.AbsentValue
for length in 0..<128:
  # Authenticate each truncated value independently before the typed reader rejects its complete extent.
  var truncated = newSeq[byte](length)
  for i in 0..<length: truncated[i] = entry.value[i]
  assert globalView(@[StateEntry(key: entry.key, value: truncated)], [entry.key]).readGlobalEntropy(
      ByteLimit(128)).error == GlobalProofError.InvalidValue
var suffix = entry.value
suffix.add(0)
assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalEntropy(
    ByteLimit(129)).error == GlobalProofError.InvalidValue
words[0] = default(StateEntropyWord)
assert array[32, byte](decoded[0])[0] == 1
echo "state-global-entropy-reads: ok"
