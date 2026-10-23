# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable evidence cursors bound every page, preserve progress and outlive selected image/file owners.
# @@Verification={"arc":"storage_light_proof_pagination_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/arc_evidence
import ../../../src/storage/[light_snapshot, light_state_cache, light_file_cache, state_proof,
  full_state_trie, database_identity, file_errors]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Iteration must use retained authenticated evidence even when every hash would refuse.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## No page traversal or detached copy may rehash proofs or checksums.
proc key(first: byte): StateKey =
  ## Canonical identities cover two long values, small and empty presence, and retained absence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc policy(): LightSnapshotLimits =
  ## Fixture image policy bounds complete retained evidence independently of page output.
  LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(items: ElementLimit(5),
    writes: ElementLimit(5), valueBytes: ByteLimit(68),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc budget(items = 5): LightProofPageLimits =
  ## Each page separately bounds descriptor count and individual/aggregate output.
  LightProofPageLimits(items: ElementLimit(items), nodes: ElementLimit(1245),
    valueBytes: ByteLimit(68), proof: policy().cache.proof)
proc same(actual, expected: StateProof) =
  ## Compare exact proof transport without assuming value length distinguishes presence from absence.
  assert actual.value == expected.value and actual.nodes.len == expected.nodes.len
  for index in 0..<actual.nodes.len:
    assert array[64, byte](actual.nodes[index]) == array[64, byte](expected.nodes[index])
proc transferred(image: PreparedLightSnapshot): LightProofCursor =
  ## The cursor retains a temporary restored image after its source and local handle retire.
  var bytes = image.bytes
  let restored = takeLightSnapshot(bytes, image.chainId, image.root, image.limits).value
  assert bytes.len == 0
  restored.proofCursor.value
proc cycle(image: PreparedLightSnapshot) =
  ## Retire page payloads, retained continuations and failed reads before the ARC observation.
  let start = image.proofCursor.value
  var short = budget()
  short.valueBytes = ByteLimit(32)
  assert start.readPage(short).error == LightSnapshotError.LimitExceeded
  let page = start.readPage(budget(2)).value
  let next = page.nextCursor
  assert page.len == 2 and not next.finished
  var detached = page.proofs
  detached[0].proof.value[0] = 99
  detached[0].proof.nodes[0] = default(EncodedStateNode)
  assert page.proofs[0].proof.value[0] == 0
  assert start.readPage(budget(2)).value.proofs[0].proof.value[0] == 0
  assert next.readPage(budget()).value.nextCursor.finished
proc prepared(image: PreparedLightSnapshot, trie: FullStateTrie) =
  ## Every cardinality and exact payload ceiling preserves canonical order, progress, retry and root binding.
  let identities = [key(0), key(64), key(128), key(192), key(255)]
  let start = image.proofCursor.value
  assert start.initialized and not start.finished
  assert array[32, byte](start.root) == array[32, byte](image.root)
  assert not default(LightProofCursor).initialized
  assert default(LightProofCursor).readPage(budget()).error == LightSnapshotError.Uninitialized
  assert default(PreparedLightSnapshot).proofCursor.error == LightSnapshotError.Uninitialized
  resetHash(1)
  for items in 1..6:
    var cursor = start
    var seen = 0
    while not cursor.finished:
      # A successful nonterminal call must produce evidence and advance without any key-list staging.
      let page = cursor.readPage(budget(items)).value
      assert page.len > 0 and page.len <= items
      let proofs = page.proofs
      for proof in proofs:
        assert array[31, byte](proof.key) == array[31, byte](identities[seen])
        inc seen
      cursor = page.nextCursor
    assert seen == identities.len
    let terminal = cursor.readPage(default(LightProofPageLimits)).value
    assert terminal.len == 0 and terminal.nextCursor.finished
  assert start.readPage(default(LightProofPageLimits)).error == LightSnapshotError.LimitExceeded
  var short = budget()
  short.proof.valueBytes = ByteLimit(32)
  assert start.readPage(short).error == LightSnapshotError.LimitExceeded
  short = budget()
  short.nodes = ElementLimit(0)
  assert start.readPage(short).error == LightSnapshotError.LimitExceeded
  short = budget()
  short.valueBytes = ByteLimit(33)
  let first = start.readPage(short).value
  assert first.len == 1
  let second = first.nextCursor.readPage(short).value
  assert second.len == 2
  short.proof.valueBytes = ByteLimit(2)
  assert second.nextCursor.readPage(short).error == LightSnapshotError.LimitExceeded
  let last = second.nextCursor.readPage(budget()).value
  assert last.len == 2 and last.nextCursor.finished
  let maximum = high(uint64)
  let unlimited = LightProofPageLimits(items: ElementLimit(maximum), nodes: ElementLimit(maximum),
    valueBytes: ByteLimit(maximum),
    proof: StateProofLimits(nodes: ElementLimit(maximum), valueBytes: ByteLimit(maximum)))
  assert start.readPage(unlimited).value.len == 5
  assert calls() == 0
  resetHash(0)
  let exactPath = trie.prove(key(0), policy().cache.proof).value
  var exact = budget()
  exact.nodes = ElementLimit(exactPath.nodes.len)
  exact.valueBytes = ByteLimit(33)
  same(start.readPage(exact).value.proofs[0].proof, exactPath)
  let all = transferred(image).readPage(budget()).value
  for proof in all.proofs:
    same(proof.proof, trie.prove(proof.key, policy().cache.proof).value)
    let verified = verifyStateProof(image.root, proof.key, proof.proof, policy().cache.proof).value
    assert verified.kind == image.cache.lookup(proof.key).value.kind
  let changed = image.forget([key(0)]).value
  assert changed.proofCursor.value.readPage(budget(1)).value.proofs[0].proof.value.len == 2
  assert start.readPage(budget(1)).value.proofs[0].proof.value.len == 33
  for iteration in 0..<10: cycle(image)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(image)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_proof_pagination", 1000, before, after)
proc empty() =
  ## Empty images are terminal immediately; retained zero-node absences remain real pageable entries.
  let blank = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy()).value
  let terminal = blank.proofCursor.value
  assert terminal.finished and terminal.readPage(default(LightProofPageLimits)).value.len == 0
  let absent = [LightStateProof(key: key(128)), LightStateProof(key: key(0))]
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), absent, policy()).value
  let zero = LightProofPageLimits(items: ElementLimit(1))
  resetHash(1)
  let first = image.proofCursor.value.readPage(zero).value
  assert first.len == 1 and first.proofs[0].proof.nodes.len == 0
  assert not first.nextCursor.finished
  assert first.nextCursor.readPage(zero).value.nextCursor.finished
  assert calls() == 0
  resetHash(0)
proc files(image: PreparedLightSnapshot) {.raises.} =
  ## A cursor retained from a reopened file owns no directory lease and survives complete file removal.
  let path = "storage-light-proof-pagination"
  let config = LightFileConfig(root: image.root, limits: image.limits)
  var owner = default(LightFileCache)
  defer:
    resetHash(0)
    if owner.opened: discard owner.close
  assert initializeLightFileCache(owner, path, config, image).error == FileError.None
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  let cursor = owner.preparedSnapshot.value.proofCursor.value
  assert owner.close == FileError.None
  var current = path & "/CURRENT"
  var lock = path & "/LOCK"
  var directory = path
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lock.toCString()) == 0
  assert posix.rmdir(directory.toCString()) == 0
  resetHash(1)
  assert cursor.readPage(budget()).value.len == 5 and calls() == 0
  resetHash(0)
proc main() {.raises.} =
  ## Complete independent flat-map hashing fixes authority before building the retained evidence fixture.
  resetHash(0)
  var other = newSeq[byte](33)
  for index in 0..<33: other[index] = 7
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)),
    StateEntry(key: key(64), value: @[1'u8, 2'u8]), StateEntry(key: key(128)),
    StateEntry(key: key(192), value: other)]
  let bounds = StateTrieLimits(items: ElementLimit(4), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(68))
  let root = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  var proofs: seq[LightStateProof] = @[]
  for first in [255'u8, 0'u8, 128'u8, 64'u8, 192'u8]:
    proofs.add(LightStateProof(key: key(first), proof: trie.prove(key(first), policy().cache.proof).value))
  let image = prepareLightSnapshot(default(StorageChainId), root, proofs, policy()).value
  prepared(image, trie)
  empty()
  files(image)
try:
  main()
except:
  quit(2)
echo "PASS storage light proof pagination: bounded advancing pages, immutable continuations and detached evidence"
