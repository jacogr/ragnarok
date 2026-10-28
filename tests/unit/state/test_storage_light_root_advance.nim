# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent roots qualify replacement knowledge, exact source binding, durable publication, explicit cleanup and immutable reader lifetimes.
# @@Verification={"arc":"storage_light_root_advance_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../support/storage_light_journal
import ../../support/storage_light_root
import ../../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../../src/storage/light_journal_manifest as storage_light_journal_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Pure refusal and prepared publication must not redo destination proof/image hashing.
proc refuseAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Manifest and anchor hashing each receive a real late provider refusal.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe exact provider work independently of successful result construction.
proc path(label: string): string =
  ## Native suite cwd is already an isolated ignored namespace; fixture paths add no missing parent directories.
  "light-root-" & $storageProcessId() & "-" & label
proc seed(directory: string, fixture: LightRootFixture) =
  ## Initialize and explicitly retire one source-root owner before each independently opened test.
  var owner = default(LightJournalCache)
  assert initializeLightJournalCache(owner, directory, fixture.oldConfig, fixture.source).error == FileError.None
  assert owner.close == FileError.None
proc prepare(owner: LightJournalCache, fixture: LightRootFixture): PreparedLightRootAdvance =
  ## Explicit destination root selection is separate from the opaque target image's embedded root.
  prepareLightRootAdvance(owner, owner.epoch.value, owner.sequence.value,
    fixture.newConfig.root, fixture.destination).value
proc cycle(owner: LightJournalCache, fixture: LightRootFixture) =
  ## Late private metadata refusal and successful copied candidates all retire before the caller samples ARC.
  refuseAfter(1)
  assert prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0),
    fixture.newConfig.root, fixture.destination).error == FileError.BackendFailure
  resetHash(0)
  let candidate = prepare(owner, fixture)
  let copied = candidate
  assert uint64(copied.epoch) == 2 and copied.snapshot.encodedBytes ==
      fixture.destination.encodedBytes
proc mutation(owner: LightJournalCache, fixture: LightRootFixture) =
  ## Caller-owned proof/key and extracted-byte mutation cannot retag or alter the sealed root candidate or source readers.
  let transport = fixture.destination.prove(lightKey(0), LightProofReadLimits(entries: ElementLimit(1),
    proof: fixture.newConfig.snapshot.cache.proof)).value
  var proofs = @[LightStateProof(key: lightKey(0), proof: transport)]
  let image = prepareLightSnapshot(fixture.newConfig.chain, fixture.newConfig.root, proofs,
      fixture.newConfig.snapshot).value
  let candidate = prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0),
      fixture.newConfig.root, image).value
  let original = candidate.snapshot.bytes
  proofs[0].proof.value[0] = 99
  proofs[0].key = lightKey(255)
  var detached = candidate.snapshot.bytes
  detached[0] = 0
  assert candidate.snapshot.encodedBytes == original, "prepared target owns immutable canonical evidence"
  assert candidate.snapshot.cache.lookup(lightKey(0)).value.bytes[0] == 9, "prepared target lookup is independent of caller proof mutation"
  assert candidate.snapshot.cache.lookup(lightKey(255)).error == LightCacheError.UnknownKey
  assert owner.snapshot.value.lookup(lightKey(0)).value.bytes[0] == 7, "caller mutation cannot affect source root reader"
proc normal(fixture: LightRootFixture) {.raises.} =
  ## New knowledge replaces all source evidence while old caches/readers and exact source-bound plans keep their original meaning.
  let directory = path("normal")
  seed(directory, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
  mutation(owner, fixture)
  let held = owner.preparedSnapshot.value
  let reader = owner.snapshot.value
  let cursor = held.proofCursor.value
  let oldFrame = prepareLightDelta(held, LightDeltaSequence(1), [], [lightKey(32)],
      fixture.oldConfig.journal.frame).value
  let oldBatch = prepareLightJournalBatch(owner, [LightJournalEdit(forgotten: @[lightKey(32)])]).value
  let oldCompaction = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(0)).value
  let original = readFile(directory & "/CURRENT")
  let oldBytes = readFile(lightChild(directory, ManagedFileKind.Journal))
  resetIo()
  resetHash(0)
  let plan = prepare(owner, fixture)
  assert calls() == 2, "only manifest and anchor hashes in root preparation"
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "root preparation performs no IO"
  assert uint64(plan.epoch) == 2 and uint64(plan.sequence) == 0, "distinct epoch and preserved update sequence"
  assert array[32, byte](plan.root) == array[32, byte](fixture.newConfig.root), "explicit destination root binding"
  for index in 0..<10: cycle(owner, fixture)
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(owner, fixture)
  let after = getOccupiedMem()
  assert before == after, "root candidates retain no source image or native lease chain"
  recordArcRelease("storage_light_root_advance", 1000, before, after)
  resetHash(1)
  resetIo()
  let changed = owner.advanceRoot(plan)
  assert changed.error == FileError.None and changed.value.retirement == FileError.None, "confirmed root selection"
  assert calls() == 0, "opaque publication rehashes no destination evidence"
  resetHash(0)
  assert ioCalls(writeIo) == 3 and ioCalls(syncIo) == 8 and ioCalls(renameIo) == 1, "checkpoint anchor and atomic selection barriers"
  assert array[32, byte](changed.value.previousRoot) == array[32, byte](fixture.oldConfig.root), "receipt preserves old root"
  assert array[32, byte](changed.value.root) == array[32, byte](fixture.newConfig.root), "receipt confirms accepted destination root"
  assert uint64(changed.value.previousEpoch) == 1 and uint64(changed.value.epoch) == 2 and uint64(
      changed.value.sequence) == 0
  let selected = owner.snapshot.value
  assert selected.lookup(lightKey(0)).value.bytes[0] == 9, "changed positive value comes only from new proof"
  assert selected.lookup(lightKey(64)).value.bytes.len == 0, "new present-empty knowledge"
  assert selected.lookup(lightKey(128)).value.kind == StateLookupKind.Absent, "old present-empty becomes explicitly proved absence"
  assert selected.lookup(lightKey(255)).error == LightCacheError.UnknownKey, "old negative knowledge is not carried into destination"
  assert selected.lookup(lightKey(32)).error == LightCacheError.UnknownKey, "unchanged bytes do not authorize implicit proof carry"
  assert reader.lookup(lightKey(0)).value.bytes[0] == 7 and reader.lookup(lightKey(
      255)).value.kind == StateLookupKind.Absent
  assert array[32, byte](cursor.root) == array[32, byte](fixture.oldConfig.root), "retained proof cursor keeps original root"
  assert readFile(lightChild(directory, ManagedFileKind.Journal)) == oldBytes, "old-root journal remains untouched"
  assert readFile(lightChild(directory, ManagedFileKind.Snapshot)) == lightText(
      fixture.source.encodedBytes), "old-root checkpoint remains untouched"
  resetIo()
  assert owner.advanceRoot(plan).error == FileError.StaleView, "committed root transition cannot be repeated"
  assert owner.append(oldFrame).error == FileError.WrongIdentity, "old-root frame refuses"
  assert owner.append(oldBatch).error == FileError.WrongIdentity, "old-root group refuses"
  assert owner.compact(oldCompaction).error == FileError.WrongIdentity, "old-root compaction refuses"
  assert owner.discardUnselectedRootAdvance(plan) == FileError.InvalidRetention, "selected target cannot be discarded"
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "stale/wrong-root operations perform no IO"
  assert owner.update([fixture.following], []).error == FileError.None, "ordinary new-root proof update remains available"
  assert uint64(owner.sequence.value) == 1 and owner.snapshot.value.lookup(lightKey(
      32)).value.bytes[0] == 11
  let back = prepareLightRootAdvance(owner, ManagedEpoch(2), LightDeltaSequence(1),
      fixture.oldConfig.root, fixture.source).value
  assert owner.advanceRoot(back).error == FileError.None, "independently accepted return root uses another physical epoch"
  resetIo()
  assert owner.advanceRoot(plan).error == FileError.StaleView and ioCalls(writeIo) == 0, "equal root/image after return does not revive an old plan"
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, directory, fixture.newConfig) == FileError.WrongIdentity, "wrong independently expected root never falls back"
  assert not owner.opened and readFile(directory & "/CURRENT") != original, "wrong-root refusal preserves selected transport"
  assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
  assert uint64(owner.epoch.value) == 3 and uint64(owner.sequence.value) == 1, "strict reopen preserves root-return position"
  assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "reclaim old source-root epoch explicitly"
  assert owner.cleanupRetiredEpoch(ManagedEpoch(2)) == FileError.None, "reclaim different-root retired epoch explicitly"
  assert owner.close == FileError.None
  assert held.encodedBytes == fixture.source.encodedBytes and reader.lookup(lightKey(
      0)).value.bytes[0] == 7, "original reader survives all root lifetimes"
  retireRootEpoch(directory, ManagedEpoch(3))
  retireLightJournal(directory)
proc refusals(fixture: LightRootFixture) {.raises.} =
  ## Old positive/negative proofs, independent identity, policy, provider and stale positions refuse without changing selected knowledge.
  let directory = path("refusals")
  seed(directory, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetHash(0)
    resetIo()
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
  for index in [0, 1, 3]:
    # Source proofs include changed, unchanged-value and stale-negative cases; none gains new-root trust by retention.
    assert prepareLightSnapshot(fixture.oldConfig.chain, fixture.newConfig.root,
      [fixture.sourceProofs[index]], fixture.oldConfig.snapshot).error ==
          LightSnapshotError.ProofFailure
  var wrongChain = default(array[32, byte])
  wrongChain[0] = 99
  let foreign = prepareLightSnapshot(StorageChainId(wrongChain), fixture.newConfig.root, [],
      fixture.oldConfig.snapshot).value
  var policy = fixture.oldConfig.snapshot
  policy.cache.writes = ElementLimit(3)
  let widened = prepareLightSnapshot(fixture.oldConfig.chain, fixture.newConfig.root, [], policy).value
  resetHash(1)
  resetIo()
  assert prepareLightRootAdvance(owner, ManagedEpoch(2), LightDeltaSequence(0),
      fixture.newConfig.root, fixture.destination).error == FileError.StaleView
  assert prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(1),
      fixture.newConfig.root, fixture.destination).error == FileError.StaleView
  assert prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0),
      fixture.oldConfig.root, fixture.source).error == FileError.InvalidBatch
  assert prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0),
      fixture.oldConfig.root, fixture.destination).error == FileError.WrongIdentity
  assert prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0),
      fixture.newConfig.root, foreign).error == FileError.WrongIdentity
  assert prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0),
      fixture.newConfig.root, widened).error == FileError.InvalidBatch
  assert owner.advanceRoot(default(PreparedLightRootAdvance)).error == FileError.Uninitialized
  assert owner.discardUnselectedRootAdvance(default(PreparedLightRootAdvance)) ==
      FileError.Uninitialized
  assert calls() == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "known refusal precedes provider/IO work"
  resetHash(0)
  for count in 0..<2:
    refuseAfter(cint(count))
    assert prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0),
        fixture.newConfig.root, fixture.destination).error == FileError.BackendFailure
    assert calls() == cint(count+1), "exact metadata provider refusal"
    assert owner.preparedSnapshot.value.encodedBytes == fixture.source.encodedBytes, "provider refusal preserves source"
  resetHash(0)
  let plan = prepare(owner, fixture)
  assert owner.update([], [lightKey(32)]).error == FileError.None
  resetIo()
  assert owner.advanceRoot(plan).error == FileError.StaleView and ioCalls(writeIo) == 0, "ordinary append stales prepared root selection"
  assert owner.discardUnselectedRootAdvance(plan) == FileError.None, "same-epoch later append permits absent candidate cleanup"
  assert owner.close == FileError.None
  var changed = fixture.oldConfig
  changed.journal.frames = ElementLimit(63)
  assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
  let rebound = prepare(owner, fixture)
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, directory, changed) == FileError.None
  resetIo()
  assert owner.advanceRoot(rebound).error == FileError.InvalidBatch, "reopened journal policy cannot silently change plan binding"
  assert ioCalls(writeIo) == 0
  assert owner.close == FileError.None
  retireLightJournal(directory)
proc emptyReadOnly() {.raises.} =
  ## Full replacement evidence is independent of zero future writes, and an empty trusted destination still leaves every key unknown.
  let fixture = rootFixture(ElementLimit(0))
  for empty in [false, true]:
    let directory = path("read-only-" & $empty)
    seed(directory, fixture)
    var owner = default(LightJournalCache)
    defer:
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
    let root = if empty: default(StateRoot) else: fixture.newConfig.root
    let image = if empty: prepareLightSnapshot(fixture.oldConfig.chain, root, [],
        fixture.oldConfig.snapshot).value else: fixture.destination
    let plan = prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(0), root, image).value
    assert owner.advanceRoot(plan).error == FileError.None, "read-only root replacement is valid maintenance"
    assert uint64(owner.preparedSnapshot.value.limits.cache.writes) == 0
    if empty:
      assert owner.snapshot.value.len == 0 and owner.snapshot.value.lookup(lightKey(0)).error ==
          LightCacheError.UnknownKey
    else:
      assert owner.snapshot.value.lookup(lightKey(0)).value.bytes[0] == 9
    assert owner.update([], []).error == FileError.None, "empty ordinary edit remains permitted within zero write capacity"
    assert owner.update([fixture.following], []).error == FileError.LimitExceeded
    assert owner.close == FileError.None
    var config = fixture.oldConfig
    config.root = root
    assert openLightJournalCache(owner, directory, config) == FileError.None
    assert owner.close == FileError.None
    retireRootEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc failures(fixture: LightRootFixture) {.raises.} =
  ## Every physical publication phase preserves old/new root distinction and separates confirmed selection from old-handle retirement.
  for mode in 0..<10:
    let directory = path("failure-" & $mode)
    seed(directory, fixture)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
    let plan = prepare(owner, fixture)
    let original = readFile(directory & "/CURRENT")
    if mode == 6: writeFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)), "unknown target sentinel")
    if mode == 7: writeFile(directory & "/CURRENT.next", "unknown pending sentinel")
    resetIo()
    case mode
    of 0: armIo(writeIo, 0, 1, failedIo)
    of 1: armIo(writeIo, 1, 1, failedIo)
    of 2: armIo(syncIo, 6, 1, failedIo)
    of 3: armIo(renameIo, 0, 1, failedIo)
    of 4: armIo(syncIo, 7, 1, failedIo)
    of 5: armIo(closeIo, 3, 1, failedIo)
    of 8: armIo(readIo, 0, 1, failedIo)
    of 9: armIo(closeIo, 0, 1, failedIo)
    else: discard # Existing exact target/staging names are independently authored refusals, not injected IO.
    let changed = owner.advanceRoot(plan)
    assert pendingIo() == 0, "intended root publication fault consumed"
    resetIo()
    let selectedNew = mode == 4 or mode == 5
    if mode == 5:
      assert changed.error == FileError.None and changed.value.retirement == FileError.IoFailure, "confirmed root survives old-handle close failure"
      assert array[32, byte](changed.value.root) == array[32, byte](fixture.newConfig.root)
    else:
      let expected = if mode == 4: FileError.PublishedUnsynced
        elif mode == 6 or mode == 7: FileError.AlreadyExists else: FileError.IoFailure
      assert changed.error == expected, "root publication preserves exact IO/refusal cause"
    if mode == 6:
      assert owner.preparedSnapshot.error == FileError.None, "pure candidate-name refusal preserves source confirmation"
    else:
      assert owner.snapshot.error == FileError.RecoveryRequired, "uncertain root owner grants no fresh view"
      assert owner.advanceRoot(plan).error == FileError.RecoveryRequired, "uncertain root transition requires explicit close"
    if not selectedNew: assert readFile(directory & "/CURRENT") == original
    assert owner.close == FileError.None
    let wrong = if selectedNew: fixture.oldConfig else: fixture.newConfig
    let right = if selectedNew: fixture.newConfig else: fixture.oldConfig
    let forensic = readFile(directory & "/CURRENT")
    assert openLightJournalCache(owner, directory, wrong) == FileError.WrongIdentity, "wrong independently expected root cannot fall back"
    assert not owner.opened and readFile(directory & "/CURRENT") == forensic
    assert openLightJournalCache(owner, directory, right) == FileError.None, "independently expected selected root strictly verifies"
    if selectedNew:
      assert uint64(owner.epoch.value) == 2 and owner.preparedSnapshot.value.encodedBytes ==
          fixture.destination.encodedBytes
      assert owner.discardUnselectedRootAdvance(plan) == FileError.InvalidRetention, "selected root candidate is never cleanup authority"
      assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "explicit cross-root retired cleanup"
    elif mode == 6:
      resetIo()
      assert owner.discardUnselectedRootAdvance(plan) == FileError.RecoveryMismatch
      assert ioCalls(unlinkIo) == 0, "unknown candidate refuses before deletion"
      assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))) == "unknown target sentinel"
    else:
      if mode == 7:
        # A bad final preflight must preserve the earlier complete candidate files too.
        let checkpoint = readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)))
        let journal = readFile(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2)))
        resetIo()
        assert owner.discardUnselectedRootAdvance(plan) == FileError.RecoveryMismatch
        assert ioCalls(unlinkIo) == 0 and readFile(directory & "/CURRENT.next") == "unknown pending sentinel"
        assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))) == checkpoint
        assert readFile(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2))) == journal
        assert owner.discardPending == FileError.None, "explicit staging-only discard requires current selected head"
      assert owner.discardUnselectedRootAdvance(plan) == FileError.None, "remove only matching unselected root prefixes"
      resetIo()
      assert owner.discardUnselectedRootAdvance(plan) == FileError.None and ioCalls(syncIo) > 0, "already-absent cleanup still synchronizes"
      assert owner.preparedSnapshot.value.encodedBytes == fixture.source.encodedBytes
    assert owner.close == FileError.None
    retireRootEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc cleanupRetry(fixture: LightRootFixture) {.raises.} =
  ## A partial target remains explicitly cleanable after same-epoch appends; a last-unlink barrier failure permits a durable absent-name retry.
  for barrierFailure in [false, true]:
    let directory = path("cleanup-" & $barrierFailure)
    seed(directory, fixture)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
    let plan = prepare(owner, fixture)
    limitWrites(64)
    armIo(writeIo, 1, 1, failedIo)
    assert owner.advanceRoot(plan).error == FileError.IoFailure and pendingIo() == 0
    resetIo()
    assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))).len == 64, "actual bounded partial target checkpoint"
    assert owner.close == FileError.None
    assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
    assert owner.update([], [lightKey(32)]).error == FileError.None
    assert owner.advanceRoot(plan).error == FileError.StaleView, "append invalidates publication position"
    resetIo()
    if barrierFailure:
      # Only the snapshot candidate exists: its last unlink succeeds before this observed directory barrier fails.
      armIo(syncIo, 0, 1, failedIo)
      assert owner.discardUnselectedRootAdvance(plan) == FileError.IoFailure and pendingIo() == 0
      assert owner.preparedSnapshot.error == FileError.None, "unselected cleanup failure preserves selected root"
      resetIo()
    assert owner.discardUnselectedRootAdvance(plan) == FileError.None, "same-epoch append permits exact candidate cleanup"
    assert ioCalls(syncIo) > 0, "cleanup confirms absence even after last-unlink barrier failure"
    let fresh = prepare(owner, fixture)
    assert owner.advanceRoot(fresh).error == FileError.None
    assert uint64(owner.sequence.value) == 1 and uint64(owner.epoch.value) == 2
    assert owner.discardUnselectedRootAdvance(plan) == FileError.InvalidRetention, "obsolete target plan cannot delete its now-selected epoch"
    assert owner.close == FileError.None
    retireRootEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc renameFile(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Maximum-counter fixtures relocate only canonical test-owned files before strict admission.
proc maxima(fixture: LightRootFixture) {.raises.} =
  ## Root selection exhausts only epoch space; the maximum ordinary-update sequence remains a valid unchanged checkpoint baseline.
  for maximumEpoch in [false, true]:
    let directory = path("max-" & $maximumEpoch)
    seed(directory, fixture)
    let epoch = if maximumEpoch: ManagedEpoch(high(uint64)) else: ManagedEpoch(1)
    let sequence = if maximumEpoch: LightDeltaSequence(0) else: LightDeltaSequence(high(uint64))
    if maximumEpoch:
      for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
        var original = lightChild(directory, kind)
        var target = lightChild(directory, kind, epoch)
        assert renameFile(original.toCString(), target.toCString()) == 0
    let manifest = prepareLightJournalManifest(fixture.source, epoch, sequence, ByteLimit(
        LightJournalManifestBytes)).value
    writeFile(directory & "/CURRENT", lightText(manifest.bytes))
    writeFile(lightChild(directory, ManagedFileKind.Journal, epoch), lightText(
        encodeLightJournalAnchor(manifest, ByteLimit(98)).value))
    var owner = default(LightJournalCache)
    defer:
      resetHash(0)
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
    if maximumEpoch:
      resetHash(1)
      resetIo()
      assert prepareLightRootAdvance(owner, epoch, sequence, fixture.newConfig.root,
          fixture.destination).error == FileError.EpochExhausted
      assert calls() == 0 and ioCalls(writeIo) == 0, "epoch cannot wrap and refuses before provider work"
      resetHash(0)
    else:
      let plan = prepare(owner, fixture)
      assert owner.advanceRoot(plan).error == FileError.None, "maximum update sequence is preserved without addition"
      assert uint64(owner.sequence.value) == high(uint64)
      assert owner.update([], []).error == FileError.LimitExceeded, "subsequent ordinary sequence cannot wrap"
    assert owner.close == FileError.None
    let config = if maximumEpoch: fixture.oldConfig else: fixture.newConfig
    assert openLightJournalCache(owner, directory, config) == FileError.None
    assert uint64(owner.sequence.value) == uint64(sequence), "strict maximum baseline"
    assert owner.close == FileError.None
    if maximumEpoch: retireRootEpoch(directory, epoch)
    else: retireRootEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc physicalCycles(fixture: LightRootFixture) {.raises.} =
  ## Physical compaction and an equal-sequence root/image return must each invalidate earlier source positions.
  let directory = path("physical-cycles")
  seed(directory, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetHash(0)
    resetIo()
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, directory, fixture.oldConfig) == FileError.None
  let initial = prepare(owner, fixture)
  let compacted = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(0)).value
  assert owner.compact(compacted).error == FileError.None
  resetHash(1)
  resetIo()
  assert owner.advanceRoot(initial).error == FileError.StaleView and calls() == 0 and ioCalls(
      writeIo) == 0, "same-root same-sequence compaction stales old root plan"
  resetHash(0)
  let forward = prepare(owner, fixture)
  assert owner.advanceRoot(forward).error == FileError.None
  let back = prepareLightRootAdvance(owner, ManagedEpoch(3), LightDeltaSequence(0),
      fixture.oldConfig.root, fixture.source).value
  assert owner.advanceRoot(back).error == FileError.None
  assert uint64(owner.sequence.value) == 0 and uint64(owner.epoch.value) == 4
  assert owner.preparedSnapshot.value.encodedBytes == fixture.source.encodedBytes
  resetHash(1)
  resetIo()
  assert owner.advanceRoot(forward).error == FileError.StaleView and calls() == 0 and ioCalls(
      writeIo) == 0, "equal root image and sequence do not revive a prior physical source"
  resetHash(0)
  for epoch in 1'u64..3'u64:
    assert owner.cleanupRetiredEpoch(ManagedEpoch(epoch)) == FileError.None
  assert owner.close == FileError.None
  assert forward.snapshot.encodedBytes == fixture.destination.encodedBytes, "prepared target outlives source owner and all retired files"
  retireRootEpoch(directory, ManagedEpoch(4))
  retireLightJournal(directory)
proc main() {.raises.} =
  ## Each fixture has independent root provenance and no state/application adapters.
  let fixture = rootFixture()
  normal(fixture)
  refusals(fixture)
  emptyReadOnly()
  failures(fixture)
  cleanupRetry(fixture)
  maxima(fixture)
  physicalCycles(fixture)
try:
  main()
except:
  quit(2)
echo "PASS light root advancement: independent roots, replacement knowledge, retained readers, exact position/policy and durable selection"
