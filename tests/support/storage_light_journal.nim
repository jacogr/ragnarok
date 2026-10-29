# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete-root light journal fixtures support real IO and process-crash qualification without application integration.
import std/assertions
import std/posix/posix
import ./storage_io
import ../../src/storage/light/journal/[cache as light_journal_cache,
    replay as light_journal_replay]
import ../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../src/storage/state_proof
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/database_identity
import ../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../src/storage/file/errors as file_errors
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
type
  LightJournalFixture* = object ## Detached proof images and transitions retain no complete trie or native lease.
    config*: LightJournalConfig
    initial*: PreparedLightSnapshot
    next*: PreparedLightDelta
    following*: PreparedLightDelta
proc lightKey*(first: byte): StateKey =
  ## Fixed query identities distinguish inclusion, known absence and forgotten evidence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc lightFixture*(): LightJournalFixture =
  ## Independently hash a complete two-key map before deriving partial evidence and forward/reverse transitions.
  var value = newSeq[byte](33)
  for index in 0..<value.len: value[index] = 7
  let entries = [StateEntry(key: lightKey(0), value: value), StateEntry(key: lightKey(128))]
  let limits = StateTrieLimits(items: ElementLimit(2), nodes: TrieNodeLimit(1000),
      perValue: ByteLimit(64), totalValueBytes: ByteLimit(128))
  let root = stateTrieRoot(entries, limits).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](root)
  let config = LightJournalConfig(root: root, snapshot: LightSnapshotLimits(bytes: ByteLimit(4096),
    cache: LightCacheLimits(items: ElementLimit(4), writes: ElementLimit(4), valueBytes: ByteLimit(128),
      proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(64)))),
    journal: LightReplayLimits(bytes: ByteLimit(65536), frames: ElementLimit(64),
      frame: LightDeltaLimits(items: ElementLimit(4), bytes: ByteLimit(4096))))
  let known = LightStateProof(key: lightKey(0), proof: trie.prove(lightKey(0),
      config.snapshot.cache.proof).value)
  let absent = LightStateProof(key: lightKey(255), proof: trie.prove(lightKey(255),
      config.snapshot.cache.proof).value)
  let initial = prepareLightSnapshot(config.chain, root, [known], config.snapshot).value
  let next = prepareLightDelta(initial, LightDeltaSequence(1), [absent], [known.key],
      config.journal.frame).value
  let following = prepareLightDelta(next.snapshot, LightDeltaSequence(2), [known], [absent.key],
      config.journal.frame).value
  LightJournalFixture(config: config, initial: initial, next: next, following: following)
proc lightChild*(path: string, kind: ManagedFileKind, epoch = ManagedEpoch(1)): string =
  ## Only exact canonical fixture epochs supply filenames; no directory scan establishes selection.
  path & "/" & managedFileName(kind, epoch).value
proc lightText*(bytes: openArray[byte]): string =
  ## Independent copied comparison transport never retains a mutable borrow from prepared authority.
  result = newString(bytes.len)
  for index in 0..<bytes.len: result[index] = char(bytes[index])
proc seedLightJournal*(path: string, fixture: LightJournalFixture, partial = false) =
  ## Build a real synchronized namespace; optional partial evidence comes from a witnessed successful 64-byte write before refusal.
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    if owner.opened: discard owner.close
  assert initializeLightJournalCache(owner, path, fixture.config, fixture.initial).error == FileError.None
  if partial:
    # The real production append path must consume the exact injected second-write refusal.
    resetIo()
    limitWrites(64)
    armIo(writeIo, 1, 1, failedIo)
    assert owner.append(fixture.next).error == FileError.IoFailure
    assert pendingIo() == 0
    resetIo()
  assert owner.close == FileError.None
proc retireLightJournal*(path: string) =
  ## Remove only exact owned fixture children after every native owner and child process has retired.
  for name in ["CURRENT.next", "CURRENT", "snapshot-0000000000000001.bin",
      "journal-0000000000000001.wal", "REPLACEMENT", "KEEP", "LOCK"]:
    var file = path & "/" & name
    let removed = posix.unlink(file.toCString())
    if removed != 0: assert posix.errno() == ENOENT
  var directory = path
  assert posix.rmdir(directory.toCString()) == 0
