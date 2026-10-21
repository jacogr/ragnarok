# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual maintained primitive faults prove all-or-neither generation/verification and zero-hash policy refusal.
import std/[assertions, syncio]
import ../../../src/state/trie_proof
import ../../../src/codec/[bounded, state_layout, state_trie]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset counters and optionally refuse every hash through the maintained test observer.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse exactly after a selected successful primitive prefix.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe actual primitive attempts, including long-value hashing.
proc main() =
  ## Every source and trusted root is retained before fault injection begins.
  let maps = StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(66), nodes: TrieNodeLimit(1000))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))
  let key = chapterKey(StateChapter(0))
  let other = chapterKey(StateChapter(128))
  let entries = @[StateEntry(key: key, value: newSeq[byte](33)), StateEntry(key: other, value: @[byte 7])]
  let root = stateTrieRoot(entries, maps).value.root
  fail(0)
  let proof = generateStateProof(entries, key, maps, limits).value
  let generationCalls = calls()
  assert generationCalls == 4
  fail(0)
  assert verifyStateProof(proof, root, key, limits).error == StateProofError.None
  let verificationCalls = calls()
  assert verificationCalls == 3
  for prefix in 0..<int(generationCalls):
    # Fail at every actual node/value hash position, including after complete child work.
    failAfter(cint(prefix))
    assert generateStateProof(entries, key, maps, limits).error == StateProofError.BackendFailure
    assert calls() == cint(prefix+1)
  for prefix in 0..<int(verificationCalls):
    failAfter(cint(prefix))
    assert verifyStateProof(proof, root, key, limits).error == StateProofError.BackendFailure
    assert calls() == cint(prefix+1)
  fail(1)
  assert generateStateProof(entries, key, maps, StateProofLimits()).error ==
      StateProofError.LimitExceeded
  assert calls() == 0
  assert verifyStateProof(proof, root, key, StateProofLimits()).error ==
      StateProofError.LimitExceeded
  assert calls() == 0
  let aggregate = StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(1),
      valueBytes: ByteLimit(66))
  assert generateStateProofs(entries, [key, other], maps, limits, aggregate).error ==
      StateProofError.LimitExceeded
  assert calls() == 0
  fail(0)
  assert verifyStateProof(proof, root, key, limits).value.bytes == newSeq[byte](33)
  assert generateStateProof(entries, other, maps, limits).error == StateProofError.None
  echo "state-proof-backend: ok"
main()
