# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Locked light journal owners preserve exact policies, sparse durability, immutable readers and uncertain-IO refusal.
# @@Verification={"arc":"storage_light_journal_cache_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io]
import ../../../src/storage/light/journal/[cache as light_journal_cache,
    replay as light_journal_replay]
import ../../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    file_cache as light_file_cache, state_cache as light_state_cache]
import ../../../src/storage/state_proof
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../../src/storage/file/errors as file_errors
import ../../../src/storage/durability
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Prepared opaque appends require no provider calls; failed proof preparation never writes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Distinguish opaque transition adoption from redundant proof revalidation.
proc key(first: byte): StateKey =
  ## Independent full-state fixture queries separate present evidence from authenticated absence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc config(root: StateRoot): LightJournalConfig =
  ## Exact checkpoint policy stays external; independent journal budgets bound replay and append.
  LightJournalConfig(root: root, snapshot: LightSnapshotLimits(bytes: ByteLimit(4096),
    cache: LightCacheLimits(items: ElementLimit(4), writes: ElementLimit(4), valueBytes: ByteLimit(128),
      proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(64)))),
    journal: LightReplayLimits(bytes: ByteLimit(16384), frames: ElementLimit(64),
      frame: LightDeltaLimits(items: ElementLimit(4), bytes: ByteLimit(4096))))
proc path(suffix: string): string =
  ## Isolate exact owned filesystem fixtures across native processes and failed-run evidence.
  "storage-light-journal-" & $storageProcessId() & "-" & suffix
proc child(path: string, kind: ManagedFileKind): string =
  ## Production canonical names identify only the exact known fixture epoch for assertions and cleanup.
  path & "/" & managedFileName(kind, ManagedEpoch(1)).value
proc remove(path: string) =
  ## Retired fixtures contain only exact owned regular files; never prune another epoch or unknown child.
  for name in ["CURRENT.next", "CURRENT", "snapshot-0000000000000001.bin",
      "journal-0000000000000001.wal", "LOCK"]:
    var file = path & "/" & name
    let removed = posix.unlink(file.toCString())
    if removed != 0: assert posix.errno() == ENOENT, "only absent exact fixture files may remain"
  var directory = path
  assert posix.rmdir(directory.toCString()) == 0, "journal owner witness 43"
proc checkedOpen(path: string, settings: LightJournalConfig, expected: PreparedLightSnapshot) =
  ## Isolate all temporary owner, loaded journal and replay scratch before ARC sampling.
  var owner = default(LightJournalCache)
  assert openLightJournalCache(owner, path, settings) == FileError.None, "journal owner witness 47"
  let retained = owner.preparedSnapshot.value
  assert retained.bytes == expected.bytes, "journal owner witness 49"
  assert owner.close == FileError.None, "journal owner witness 50"
  assert not owner.opened and retained.bytes == expected.bytes, "journal owner witness 51"
proc normal(initial: PreparedLightSnapshot, incoming: LightStateProof,
    settings: LightJournalConfig): uint64 {.raises.} =
  ## Complete synchronized bootstrap and one sparse edit establish immutable readers and exact namespace behavior.
  let directory = path("normal")
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
    if contender.opened: discard contender.close
  assert not owner.opened and owner.close == FileError.Uninitialized, "journal owner witness 63"
  assert owner.snapshot.error == FileError.Uninitialized, "journal owner witness 64"
  assert owner.preparedSnapshot.error == FileError.Uninitialized, "journal owner witness 65"
  assert owner.sequence.error == FileError.Uninitialized and owner.epoch.error ==
      FileError.Uninitialized, "journal owner witness 66"
  assert owner.journalBytes.error == FileError.Uninitialized, "journal owner witness 68"
  assert owner.update([], []).error == FileError.Uninitialized, "journal owner witness 69"
  assert owner.append(default(PreparedLightDelta)).error == FileError.Uninitialized, "journal owner witness 70"
  let delta = prepareLightDelta(initial, LightDeltaSequence(1), [incoming], [key(0)],
      settings.journal.frame).value
  resetIo()
  let created = initializeLightJournalCache(owner, directory, settings, initial)
  assert created.error == FileError.None and created.value ==
      StorageDurability.FileAndDirectorySynced, "bootstrap typed refusal=" & $created.error
  result = ioCalls(syncIo)
  assert result >= 8 and result < 100, "journal owner witness 78"
  assert openLightJournalCache(contender, directory, settings) == FileError.Busy and
      not contender.opened, "journal owner witness 79"
  assert initializeLightJournalCache(owner, directory, settings, initial).error == FileError.Busy, "journal owner witness 81"
  let retained = owner.preparedSnapshot.value
  let current = readFile(directory & "/CURRENT")
  let checkpoint = readFile(child(directory, ManagedFileKind.Snapshot))
  let before = owner.journalBytes.value
  resetIo()
  resetHash(1)
  assert owner.append(delta).value == StorageDurability.FileAndDirectorySynced, "journal owner witness 88"
  assert calls() == 0, "journal owner witness 89"
  resetHash(0)
  assert ioCalls(writeIo) == 1 and ioCalls(syncIo) == 1 and ioCalls(renameIo) == 0, "journal owner witness 91"
  assert owner.journalBytes.value == before+uint64(delta.byteLength), "journal owner witness 92"
  assert readFile(directory & "/CURRENT") == current, "journal owner witness 93"
  assert readFile(child(directory, ManagedFileKind.Snapshot)) == checkpoint, "journal owner witness 94"
  assert uint64(owner.sequence.value) == 1 and uint64(owner.epoch.value) == 1, "journal owner witness 95"
  assert owner.preparedSnapshot.value.bytes == delta.snapshot.bytes, "journal owner witness 96"
  assert retained.cache.lookup(key(0)).value.kind == StateLookupKind.Present, "journal owner witness 97"
  assert owner.snapshot.value.lookup(key(0)).error == LightCacheError.UnknownKey, "journal owner witness 98"
  assert owner.snapshot.value.lookup(incoming.key).value.kind == StateLookupKind.Absent, "journal owner witness 99"
  resetIo()
  assert owner.append(delta).error == FileError.StaleView, "journal owner witness 101"
  assert owner.append(default(PreparedLightDelta)).error == FileError.Uninitialized, "journal owner witness 102"
  assert owner.update([incoming, incoming], []).error == FileError.InvalidBatch, "journal owner witness 103"
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "journal owner witness 104"
  resetHash(1)
  assert owner.update([], []).error == FileError.BackendFailure, "journal owner witness 106"
  resetHash(0)
  assert owner.preparedSnapshot.value.bytes == delta.snapshot.bytes, "journal owner witness 108"
  assert owner.close == FileError.None, "journal owner witness 109"
  assert openLightJournalCache(owner, directory, settings) == FileError.None, "journal owner witness 110"
  assert owner.preparedSnapshot.value.bytes == delta.snapshot.bytes and uint64(
      owner.sequence.value) == 1, "journal owner witness 111"
  var moved = move(owner)
  assert not owner.opened and moved.opened, "one native retirement authority transfers"
  assert owner.snapshot.error == FileError.Uninitialized, "moved-from owner is inert"
  assert moved.close == FileError.None, "retire moved journal before its directory"
  for index in 0..<10:
    # Warm the exact checked reopen path before measuring retained native/image resources.
    checkedOpen(directory, settings, delta.snapshot)
  let occupied = getOccupiedMem()
  for index in 0..<1000:
    # Each reopened native owner explicitly retires its append lease before directory retirement.
    checkedOpen(directory, settings, delta.snapshot)
  recordArcRelease("storage_light_journal_cache", 1000, occupied, getOccupiedMem())
  resetIo()
  assert openLightJournalCache(owner, directory, settings) == FileError.None, "journal owner witness 120"
  armIo(closeIo, 0, 1, failedIo)
  assert owner.close == FileError.IoFailure and not owner.opened and pendingIo() == 0, "journal owner witness 122"
  resetIo()
  assert openLightJournalCache(owner, directory, settings) == FileError.None, "journal owner witness 124"
  assert owner.close == FileError.None, "journal owner witness 125"
  var oldOwner = default(LightFileCache)
  assert openLightFileCache(oldOwner, directory, LightFileConfig(root: settings.root,
      limits: settings.snapshot)) != FileError.None, "journal owner witness 127"
  assert not oldOwner.opened, "journal owner witness 129"
  remove(directory)
proc faults(initial: PreparedLightSnapshot, incoming: LightStateProof,
    settings: LightJournalConfig) {.raises.} =
  ## Full refusal, short-prefix refusal, complete-unsynced append and zero progress all withhold current authority.
  let delta = prepareLightDelta(initial, LightDeltaSequence(1), [incoming], [key(0)],
      settings.journal.frame).value
  for mode in 0..<4:
    # Exact real native faults separate an unchanged log, incomplete frame and complete durable-reopen candidate.
    let directory = path("fault-" & $mode)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      if owner.opened: discard owner.close
    assert initializeLightJournalCache(owner, directory, settings, initial).error == FileError.None, "journal owner witness 143"
    let held = owner.preparedSnapshot.value
    let selected = readFile(directory & "/CURRENT")
    resetIo()
    case mode
    of 0: armIo(writeIo, 0, 1, failedIo)
    of 1:
      limitWrites(64)
      armIo(writeIo, 1, 1, failedIo)
    of 2: armIo(syncIo, 0, 1, failedIo)
    else: assert zeroWrites(0, 1) == 0
    let failed = owner.append(delta)
    assert failed.error == (if mode == 2: FileError.PublishedUnsynced else: FileError.IoFailure), "journal owner witness 155"
    assert pendingIo() == 0 and pendingZeroWrites() == 0, "journal owner witness 156"
    resetIo()
    assert owner.snapshot.error == FileError.RecoveryRequired, "journal owner witness 158"
    assert owner.preparedSnapshot.error == FileError.RecoveryRequired, "journal owner witness 159"
    assert owner.sequence.error == FileError.RecoveryRequired and owner.epoch.error ==
        FileError.RecoveryRequired, "journal owner witness 160"
    assert owner.journalBytes.error == FileError.RecoveryRequired, "journal owner witness 162"
    assert owner.append(delta).error == FileError.RecoveryRequired, "journal owner witness 163"
    assert owner.update([], []).error == FileError.RecoveryRequired, "journal owner witness 164"
    assert readFile(directory & "/CURRENT") == selected and held.bytes == initial.bytes, "journal owner witness 165"
    assert owner.close == FileError.None, "journal owner witness 166"
    let journal = readFile(child(directory, ManagedFileKind.Journal))
    let reopened = openLightJournalCache(owner, directory, settings)
    if mode == 1:
      # Strict open preserves every partial byte; explicit repair is a separate feature.
      assert reopened == FileError.InvalidJournal and not owner.opened, "journal owner witness 171"
      assert readFile(child(directory, ManagedFileKind.Journal)) == journal, "journal owner witness 172"
    else:
      # A failed barrier never guesses; strict reopening confirms whichever complete frame actually exists.
      assert reopened == FileError.None, "journal owner witness 175"
      assert owner.preparedSnapshot.value.bytes == (if mode ==
          2: delta.snapshot.bytes else: initial.bytes), "journal owner witness 176"
      assert owner.close == FileError.None, "journal owner witness 178"
    remove(directory)
proc limits(initial: PreparedLightSnapshot, incoming: LightStateProof,
    settings: LightJournalConfig) {.raises.} =
  ## Exact preparation policies and independent frame/count/total budgets refuse without writes or poisoning.
  for mode in 0..<4:
    # Independent limits exercise descriptor preflight, aggregate append space and exact source-policy binding.
    let directory = path("limit-" & $mode)
    var config = settings
    case mode
    of 0: config.journal.frames = ElementLimit(0)
    of 1: config.journal.frame.items = ElementLimit(0)
    of 2: config.journal.bytes = ByteLimit(98)
    else: config.journal.frame.bytes = ByteLimit(208)
    var owner = default(LightJournalCache)
    assert initializeLightJournalCache(owner, directory, config, initial).error == FileError.None, "journal owner witness 193"
    let delta = prepareLightDelta(initial, LightDeltaSequence(1), [incoming], [key(0)],
        settings.journal.frame).value
    resetIo()
    assert owner.append(delta).error == FileError.LimitExceeded, "journal owner witness 197"
    assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "journal owner witness 198"
    assert owner.preparedSnapshot.value.bytes == initial.bytes and uint64(owner.sequence.value) ==
        0, "journal owner witness 199"
    assert owner.close == FileError.None, "journal owner witness 200"
    assert openLightJournalCache(owner, directory, config) == FileError.None, "journal owner witness 201"
    assert owner.close == FileError.None, "journal owner witness 202"
    remove(directory)
  let directory = path("policy")
  var owner = default(LightJournalCache)
  defer:
    if owner.opened: discard owner.close
  assert initializeLightJournalCache(owner, directory, settings, initial).error == FileError.None, "journal owner witness 208"
  var changed = settings.snapshot
  changed.cache.writes = ElementLimit(3)
  let different = restoreLightSnapshot(initial.encodedBytes, settings.chain, settings.root, changed).value
  let delta = prepareLightDelta(different, LightDeltaSequence(1), [incoming], [key(0)],
      settings.journal.frame).value
  resetIo()
  assert owner.append(delta).error == FileError.InvalidBatch, "journal owner witness 215"
  assert ioCalls(writeIo) == 0 and owner.preparedSnapshot.value.bytes == initial.bytes, "journal owner witness 216"
  assert owner.close == FileError.None, "journal owner witness 217"
  remove(directory)
proc bootstrap(initial: PreparedLightSnapshot, settings: LightJournalConfig,
    barriers: uint64) {.raises.} =
  ## Failed bootstrap exposes no owner; the final post-rename barrier is explicitly uncertain and strictly reopenable.
  assert barriers > 0 and barriers <= uint64(high(cint)), "journal owner witness 222"
  for mode in 0..<2:
    # Compare failure before any checkpoint bytes with failure after CURRENT has actually been selected.
    let directory = path("bootstrap-" & $mode)
    var owner = default(LightJournalCache)
    resetIo()
    if mode == 0: armIo(writeIo, 0, 1, failedIo)
    else: armIo(syncIo, cint(barriers-1), 1, failedIo)
    let failed = initializeLightJournalCache(owner, directory, settings, initial)
    assert failed.error == (if mode == 0: FileError.IoFailure else: FileError.PublishedUnsynced), "journal owner witness 231"
    assert not owner.opened and pendingIo() == 0, "journal owner witness 232"
    resetIo()
    let reopened = openLightJournalCache(owner, directory, settings)
    if mode == 0: assert reopened != FileError.None and not owner.opened
    else:
      # Reopen validates the complete selected checkpoint and empty anchored journal under a new lease.
      assert reopened == FileError.None and owner.preparedSnapshot.value.bytes == initial.bytes, "journal owner witness 238"
      assert owner.close == FileError.None, "journal owner witness 239"
    remove(directory)
proc main() {.raises.} =
  ## Independent flat-map hashing fixes the complete root before any partial cache or journal exists.
  var raw = newSeq[byte](33)
  for index in 0..<raw.len: raw[index] = 7
  let entries = [StateEntry(key: key(0), value: raw), StateEntry(key: key(128))]
  let trieLimits = StateTrieLimits(items: ElementLimit(2), nodes: TrieNodeLimit(1000),
      perValue: ByteLimit(64), totalValueBytes: ByteLimit(128))
  let root = stateTrieRoot(entries, trieLimits).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: trieLimits)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](root), "journal owner witness 250"
  let settings = config(root)
  let known = LightStateProof(key: key(0), proof: trie.prove(key(0),
      settings.snapshot.cache.proof).value)
  let incoming = LightStateProof(key: key(255), proof: trie.prove(key(255),
      settings.snapshot.cache.proof).value)
  let initial = prepareLightSnapshot(settings.chain, root, [known], settings.snapshot).value
  let barriers = normal(initial, incoming, settings)
  faults(initial, incoming, settings)
  limits(initial, incoming, settings)
  bootstrap(initial, settings, barriers)
try:
  main()
except:
  quit(2)
echo "PASS light journal cache: locked sparse durable updates, strict reopening, exact policies and uncertain-IO retirement"
