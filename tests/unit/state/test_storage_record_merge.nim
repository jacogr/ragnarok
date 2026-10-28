# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mixed existing/new addresses merge independently of transport order and retained repository branches.
import std/assertions
import std/syncio
import ../../support/storage_samples
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
proc run() =
  ## Independently track every distinct full physical address across shuffled full/delta publications.
  let limits = storageLimits()
  let policy = FullStateTrieLimits(trie: limits.codec.trie, writes: ElementLimit(16),
    writeValueBytes: ByteLimit(1024))
  var entries: seq[StateEntry] = @[]
  for index in 0..<8: entries.add(StateEntry(key: storageKey(byte(index*32)), value: @[byte(index)]))
  var trie = newFullStateTrie(entries, policy).value
  var repository = newNodeRepository(limits)
  var addresses: seq[array[32, byte]] = @[]
  var retained = default(RepositoryView)
  var retainedRoot = default(StateRoot)
  for step in 0..<48:
    let previous = trie
    let index = step mod 8
    trie = trie.apply([TrieWrite(key: storageKey(byte(index*32)), kind: TrieWriteKind.Put,
      value: @[byte(step+8)])]).value
    entries[index].value = @[byte(step+8)]
    var batch = if step mod 2 == 0: exportFullTrie(trie, limits.codec.records).value
      else: exportTrieChanges(previous, trie, limits.codec.records).value
    batch.base = repository.snapshot.value.commitment.root
    # Reverse alternating transports; the independent tracked address set imposes no order assumption.
    if step mod 3 == 0:
      for left in 0..<batch.records.len div 2:
        let right = batch.records.high-left
        swap(batch.records[left], batch.records[right])
    for record in batch.records:
      let digest = array[32, byte](record.digest)
      var present = false
      for address in addresses:
        if address == digest: present = true # Compare full physical addresses independently of repository ordering.
      if not present: addresses.add(digest)
    let published = repository.publish(repository.snapshot.value, batch).value
    assert published.storedNodes == addresses.len
    for record in batch.records:
      let found = published.lookupNode(record.digest).value
      assert found.kind == record.kind and found.payload == record.payload
    let expected = stateTrieRoot(entries, limits.codec.trie).value
    assert array[32, byte](published.commitment.root) == array[32, byte](expected.root)
    if step == 0:
      retained = published
      retainedRoot = published.commitment.root
    # A zero-record no-op still advances generation and preserves all stored addresses.
    let unchanged = TrieExport(base: published.commitment.root, root: published.commitment.root,
      entries: uint64(published.commitment.entries), nodes: published.commitment.nodes)
    assert repository.publish(published, unchanged).value.storedNodes == addresses.len
  assert repository.close == RepositoryError.None
  let restored = retained.restoreFullTrie(retainedRoot, policy).value
  assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert restored.lookup(storageKey(32)).value.bytes == @[1'u8]
run()
echo "PASS storage record merge: shuffled new/reused addresses, immutable readers and complete roots"
