# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete-map roots and detached proof knowledge qualify storage-only root replacement without application state.
import std/assertions
import std/posix/posix
import ./storage_light_journal
import ../../src/storage/light/journal/[cache as light_journal_cache,
    replay as light_journal_replay]
import ../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../src/storage/state_proof
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/database_identity
import ../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
type
  LightRootFixture* = object ## Only immutable images, detached evidence and explicit root/configuration inputs survive fixture construction.
    source*, destination*: PreparedLightSnapshot
    oldConfig*, newConfig*: LightJournalConfig
    sourceProofs*, destinationProofs*: seq[LightStateProof]
    following*: LightStateProof
proc rootFixture*(writes = ElementLimit(4)): LightRootFixture =
  ## Two independent maps change a positive and negative lookup, retain an unchanged value and change empty presence to absence.
  var oldValue = newSeq[byte](33)
  var newValue = newSeq[byte](33)
  for index in 0..<33:
    oldValue[index] = 7
    newValue[index] = 9
  let oldEntries = [StateEntry(key: lightKey(0), value: oldValue),
    StateEntry(key: lightKey(32), value: @[11'u8]), StateEntry(key: lightKey(128))]
  let newEntries = [StateEntry(key: lightKey(0), value: newValue),
    StateEntry(key: lightKey(32), value: @[11'u8]), StateEntry(key: lightKey(64)),
    StateEntry(key: lightKey(255), value: @[5'u8])]
  let limits = StateTrieLimits(items: ElementLimit(8), nodes: TrieNodeLimit(10000),
    perValue: ByteLimit(64), totalValueBytes: ByteLimit(128))
  let oldRoot = stateTrieRoot(oldEntries, limits).value.root
  let newRoot = stateTrieRoot(newEntries, limits).value.root
  assert array[32, byte](oldRoot) != array[32, byte](newRoot), "independent distinct complete roots"
  let oldTrie = newFullStateTrie(oldEntries, FullStateTrieLimits(trie: limits)).value
  let newTrie = newFullStateTrie(newEntries, FullStateTrieLimits(trie: limits)).value
  var chain = default(array[32, byte])
  chain[0] = 17
  let policy = LightSnapshotLimits(bytes: ByteLimit(8192), cache: LightCacheLimits(
    items: ElementLimit(8), writes: writes, valueBytes: ByteLimit(128),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(64))))
  var oldProofs: seq[LightStateProof] = @[]
  var newProofs: seq[LightStateProof] = @[]
  for first in [0'u8, 32'u8, 128'u8, 255'u8]:
    oldProofs.add(LightStateProof(key: lightKey(first), proof: oldTrie.prove(lightKey(first),
        policy.cache.proof).value))
  for first in [0'u8, 64'u8, 128'u8]:
    newProofs.add(LightStateProof(key: lightKey(first), proof: newTrie.prove(lightKey(first),
        policy.cache.proof).value))
  let source = prepareLightSnapshot(StorageChainId(chain), oldRoot, oldProofs, policy).value
  let destination = prepareLightSnapshot(StorageChainId(chain), newRoot, newProofs, policy).value
  let journal = LightReplayLimits(bytes: ByteLimit(65536), frames: ElementLimit(64),
    frame: LightDeltaLimits(items: ElementLimit(4), bytes: ByteLimit(4096)))
  LightRootFixture(source: source, destination: destination,
    oldConfig: LightJournalConfig(chain: StorageChainId(chain), root: oldRoot, snapshot: policy,
        journal: journal),
    newConfig: LightJournalConfig(chain: StorageChainId(chain), root: newRoot, snapshot: policy,
        journal: journal),
    sourceProofs: oldProofs, destinationProofs: newProofs,
    following: LightStateProof(key: lightKey(32), proof: newTrie.prove(lightKey(32),
        policy.cache.proof).value))
proc retireRootEpoch*(path: string, epoch: ManagedEpoch) =
  ## Test retirement addresses only exact known owned snapshot/journal names; unknown directories are never scanned.
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    var name = lightChild(path, kind, epoch)
    if posix.unlink(name.toCString()) != 0: assert posix.errno() == ENOENT
