# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical proof readers are bounded before invocation, never retained and publish only complete authenticated caches.
# @@Verification={"arc":"storage_light_streaming_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Stream source failures must retain exact proof-attempt and private-prefix retirement evidence.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse a later proof after earlier immutable lookups were privately constructed.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Streaming never skips hashes, even when a source supplies previously seen transport.
proc key(first: byte): StateKey =
  ## Three canonical query identities distinguish long/empty presence and authenticated absence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc limits(): LightCacheLimits =
  ## Complete restoration retains the exact zero-write future mutation policy.
  LightCacheLimits(items: ElementLimit(3), writes: ElementLimit(0), valueBytes: ByteLimit(33),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33)))
proc fixture(): FullStateTrie =
  ## A separate flat-map calculator establishes the complete root before any proof reader is invoked.
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)), StateEntry(key: key(128))]
  let policy = StateTrieLimits(items: ElementLimit(3), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(33))
  let expected = stateTrieRoot(entries, policy).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: policy)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](expected)
  trie
proc proofs(trie: FullStateTrie): seq[LightStateProof] =
  ## Detached source transport follows canonical order and remains caller-owned after restoration.
  result = @[]
  for number in [0'u8, 128, 255]:
    result.add(LightStateProof(key: key(number), proof: trie.prove(key(number), limits().proof).value))
proc success(trie: FullStateTrie) =
  ## The source is called once per increasing index, and retained results cannot alias its mutable payloads.
  resetHash(0)
  var input = proofs(trie)
  var readCount = 0
  proc read(index: int): LightStateProof {.closure.} =
    ## The constructor may not revisit, skip or defer a callback index.
    assert index == readCount
    inc readCount
    input[index]
  resetHash(0)
  let restored = restoreLightStateCache(trie.commitment.root, 3, read, limits()).value
  assert readCount == 3 and calls() == 7
  assert restored.len == 3 and restored.valueBytes == 33
  assert uint64(restored.limits.writes) == 0
  assert restored.lookup(key(128)).value.kind == StateLookupKind.Present
  assert restored.lookup(key(128)).value.bytes.len == 0
  assert restored.lookup(key(255)).value.kind == StateLookupKind.Absent
  assert restored.lookup(key(64)).error == LightCacheError.UnknownKey
  assert restored.admit([input[0]]).error == LightCacheError.LimitExceeded
  input[0].proof.value[0] = 99
  input.setLen(0)
  assert restored.lookup(key(0)).value.bytes == newSeq[byte](33)
  # An empty restore does not invoke even a nonnil reader and preserves the same independent root/policy.
  readCount = 0
  resetHash(1)
  let empty = restoreLightStateCache(trie.commitment.root, 0, read, limits()).value
  assert empty.len == 0 and readCount == 0 and calls() == 0
  resetHash(0)
proc refusals(trie: FullStateTrie) =
  ## Count/native limits precede allocation/callbacks; each later source refusal discards private completed lookups.
  resetHash(0)
  var input = proofs(trie)
  var readCount = 0
  proc read(index: int): LightStateProof {.closure.} =
    ## Counters prove both strict invocation order and early termination after refusal.
    assert index == readCount
    inc readCount
    input[index]
  resetHash(0) # Fixture proof production is outside the zero-callback/hash preflight observation.
  var missingReader: nil LightProofReader = nil
  assert restoreLightStateCache(trie.commitment.root, 3, missingReader, limits()).error ==
      LightCacheError.Uninitialized
  assert restoreLightStateCache(trie.commitment.root, -1, read, limits()).error ==
      LightCacheError.LimitExceeded
  assert restoreLightStateCache(trie.commitment.root, 4, read, limits()).error ==
      LightCacheError.LimitExceeded
  var broad = limits()
  broad.items = ElementLimit(high(uint64))
  assert restoreLightStateCache(trie.commitment.root, high(int), read, broad).error ==
      LightCacheError.LengthOverflow
  assert readCount == 0 and calls() == 0, "count/native preflight"
  input[0].proof.nodes = newSeq[EncodedStateNode](250)
  resetHash(1)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).error ==
      LightCacheError.LimitExceeded
  assert readCount == 1 and calls() == 0
  resetHash(0)
  input = proofs(trie)
  input[0].proof.value = newSeq[byte](34)
  readCount = 0
  resetHash(1)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).error ==
      LightCacheError.LimitExceeded
  assert readCount == 1 and calls() == 0
  resetHash(0)
  input = proofs(trie)
  input[1] = LightStateProof(key: key(0), proof: trie.prove(key(0), limits().proof).value)
  readCount = 0
  resetHash(0)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).error ==
      LightCacheError.DuplicateKey
  assert readCount == 2 and calls() == 3
  input = proofs(trie)
  input[0] = LightStateProof(key: key(128), proof: trie.prove(key(128), limits().proof).value)
  input[1] = LightStateProof(key: key(0), proof: trie.prove(key(0), limits().proof).value)
  readCount = 0
  resetHash(0)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).error ==
      LightCacheError.InvalidProof
  assert readCount == 2 and calls() == 2
  input = proofs(trie)
  input[1] = LightStateProof(key: key(128))
  readCount = 0
  resetHash(0)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).error ==
      LightCacheError.IncompleteProof
  assert readCount == 2 and calls() == 3
  input = proofs(trie)
  input[0].proof.value[0] = 1
  readCount = 0
  resetHash(0)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).error ==
      LightCacheError.ValueMismatch
  assert readCount == 1 and calls() == 3
  input = proofs(trie)
  readCount = 0
  resetHash(0)
  assert restoreLightStateCache(default(StateRoot), 3, read, limits()).error ==
      LightCacheError.InvalidProof
  assert readCount == 1
  # Aggregate quota is checked against the validated prefix before the current proof is hashed.
  input = proofs(trie)
  broad = limits()
  broad.valueBytes = ByteLimit(32)
  readCount = 0
  resetHash(1)
  assert restoreLightStateCache(trie.commitment.root, 3, read, broad).error ==
      LightCacheError.LimitExceeded
  assert readCount == 1 and calls() == 0
  resetHash(0)
  input = proofs(trie)
  input[1].proof.value = newSeq[byte](33)
  readCount = 0
  resetHash(0)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).error ==
      LightCacheError.LimitExceeded
  assert readCount == 2 and calls() == 3
  resetHash(0)
proc emptyRoot() =
  ## Empty-root absence requires no hashes but remains authenticated evidence at that explicit complete root.
  var reads = 0
  proc read(index: int): LightStateProof {.closure.} =
    ## Even zero-node proofs follow strict ordered synchronous source invocation.
    assert index == reads
    inc reads
    LightStateProof(key: key(byte(index*128)))
  resetHash(1)
  let policy = LightCacheLimits(items: ElementLimit(2))
  let cache = restoreLightStateCache(default(StateRoot), 2, read, policy).value
  assert cache.len == 2 and cache.valueBytes == 0 and reads == 2 and calls() == 0
  assert cache.lookup(key(0)).value.kind == StateLookupKind.Absent
  assert cache.lookup(key(128)).value.kind == StateLookupKind.Absent
  assert cache.lookup(key(64)).error == LightCacheError.UnknownKey
  resetHash(0)
proc cycle(trie: FullStateTrie, input: openArray[LightStateProof]) =
  ## Callback environments and private partial cache owners retire at each constructor return/scope boundary.
  var reads = 0
  proc read(index: int): LightStateProof {.closure.} =
    ## Captured borrowed input is used synchronously and never retained by the finished cache.
    assert index == reads
    inc reads
    input[index]
  resetHash(0)
  let complete = restoreLightStateCache(trie.commitment.root, 3, read, limits()).value
  assert complete.len == 3 and reads == 3
  reads = 0
  refuseAfter(3)
  let failed = restoreLightStateCache(trie.commitment.root, 3, read, limits())
  assert failed.error == LightCacheError.BackendFailure
  assert reads == 2 and calls() == 4
  reads = 0
  resetHash(0)
  assert restoreLightStateCache(trie.commitment.root, 3, read, limits()).value.len == 3
  assert reads == 3 and complete.lookup(key(0)).value.bytes.len == 33
proc main() =
  ## Exact ARC steady state includes successful, partial-failure and retry paths with scoped closure environments.
  resetHash(0)
  let trie = fixture()
  success(trie)
  refusals(trie)
  emptyRoot()
  let input = proofs(trie)
  for iteration in 0..<10: cycle(trie, input)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(trie, input)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_streaming", 1000, before, after)
main()
echo "PASS storage light streaming: bounded canonical reader, complete proof authority and private-prefix retirement"
