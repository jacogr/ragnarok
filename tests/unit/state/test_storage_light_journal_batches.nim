# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded multi-update preparation keeps one final candidate; one-barrier append preserves exact prefix recovery and immutable readers.
# @@Verification={"arc":"storage_light_journal_batches_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io, storage_light_journal]
import ../../../src/storage/light/journal/[cache as light_journal_cache,
    replay as light_journal_replay, manifest as light_journal_manifest]
import ../../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../../src/storage/file/errors as file_errors
import ../../../src/storage/durability
import ../../../src/codec/bounded
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Preparation failures are independent from actual append IO and cannot poison an unchanged owner.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Every observed preparation provider boundary receives its own exact refusal.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Prepared append performs no proof, image or frame hashing.
proc edits(fixture: LightJournalFixture): array[2, LightJournalEdit] =
  ## Independent ordinary frame fixtures supply the exact two consecutive proof updates.
  result = default(array[2, LightJournalEdit])
  let known = LightStateProof(key: lightKey(0), proof: fixture.initial.prove(lightKey(0),
    LightProofReadLimits(entries: ElementLimit(1),
        proof: fixture.config.snapshot.cache.proof)).value)
  let absent = LightStateProof(key: lightKey(255), proof: fixture.next.snapshot.prove(lightKey(255),
    LightProofReadLimits(entries: ElementLimit(1),
        proof: fixture.config.snapshot.cache.proof)).value)
  result[0] = LightJournalEdit(proofs: @[absent], forgotten: @[lightKey(0)])
  result[1] = LightJournalEdit(proofs: @[known], forgotten: @[lightKey(255)])
proc candidateCycle(owner: LightJournalCache, changes: openArray[LightJournalEdit], hashes: cint) =
  ## All intermediate images, proof outcomes and aggregate transport retire before the caller samples ARC.
  refuseAfter(hashes-1)
  assert prepareLightJournalBatch(owner, changes).error == FileError.BackendFailure, "late provider refusal retires private earlier frames"
  resetHash(0)
  let prepared = prepareLightJournalBatch(owner, changes).value
  let copied = prepared
  assert copied.frameCount == 2 and uint64(copied.sequence) == 2, "exact immutable copied batch"
proc normal(fixture: LightJournalFixture, changes: openArray[LightJournalEdit]) {.raises.} =
  ## Prepare privately, append once, strictly reopen exact bytes and reject both logical and physical stale candidates.
  let path = "light-batch-normal-" & $storageProcessId()
  seedLightJournal(path, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None
  let retained = owner.snapshot.value
  let original = readFile(lightChild(path, ManagedFileKind.Journal))
  assert not default(PreparedLightJournalBatch).initialized, "default batch grants no candidate"
  assert owner.append(default(PreparedLightJournalBatch)).error == FileError.Uninitialized, "default candidate refuses"
  resetIo()
  resetHash(0)
  var mutable = edits(fixture)
  let batch = prepareLightJournalBatch(owner, mutable).value
  let hashes = calls()
  mutable[1].proofs[0].proof.value[0] = 99
  mutable[0].forgotten[0] = lightKey(128)
  # Later caller edits cannot alias prepared transport, its final image or the independent source reader.
  assert batch.snapshot.cache.lookup(lightKey(0)).value.bytes[0] == 7, "prepared lookup owns immutable value bytes"
  assert retained.lookup(lightKey(0)).value.bytes[0] == 7, "source lookup is independent of caller proof mutation"
  assert hashes > 0 and hashes < 64, "bounded actual preparation provider calls"
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "preparation performs no IO"
  assert batch.frameCount == 2 and uint64(batch.sequence) == 2, "exact final sequence and frame count"
  assert batch.byteLength == fixture.next.byteLength+fixture.following.byteLength, "exact canonical concatenated extent"
  assert batch.snapshot.bytes == fixture.following.snapshot.bytes, "exact final candidate image"
  for successful in 0..<int(hashes):
    # Every provider refusal releases private earlier frames and leaves the source confirmed and retryable.
    refuseAfter(cint(successful))
    assert prepareLightJournalBatch(owner, changes).error == FileError.BackendFailure, "typed batch preparation refusal"
    assert calls() == cint(successful+1), "consume exact provider refusal"
    assert uint64(owner.sequence.value) == 0 and owner.preparedSnapshot.value.bytes ==
        fixture.initial.bytes, "pure refusal preserves source"
  resetHash(0)
  for index in 0..<10: candidateCycle(owner, changes, hashes)
  let before = getOccupiedMem()
  for index in 0..<1000: candidateCycle(owner, changes, hashes)
  let after = getOccupiedMem()
  assert before == after, "batch candidates retain no intermediate-image chain"
  recordArcRelease("storage_light_journal_batches", 1000, before, after)
  resetIo()
  resetHash(1)
  assert owner.append(batch).value == StorageDurability.FileAndDirectorySynced, "one confirmed grouped append"
  assert calls() == 0, "prepared append hashes nothing"
  assert ioCalls(writeIo) == 1 and ioCalls(syncIo) == 1 and ioCalls(renameIo) == 0, "one ordinary write and one file barrier"
  resetHash(0)
  let expected = original & lightText(fixture.next.encodedBytes) & lightText(
      fixture.following.encodedBytes)
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == expected, "exact independently authored frame bytes"
  assert uint64(owner.sequence.value) == 2 and owner.preparedSnapshot.value.bytes ==
      fixture.following.snapshot.bytes, "publish only final confirmed image"
  resetIo()
  assert owner.append(batch).error == FileError.StaleView and ioCalls(writeIo) == 0, "logical stale batch refuses before IO"
  let future = prepareLightJournalBatch(owner, changes).value
  let replacement = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(2)).value
  assert owner.compact(replacement).error == FileError.None, "advance only physical checkpoint epoch"
  resetIo()
  assert owner.append(future).error == FileError.StaleView and ioCalls(writeIo) == 0, "same-sequence physical stale batch refuses"
  assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "retire original epoch after confirmed compaction"
  assert owner.close == FileError.None, "retire native owner while candidates remain alive"
  assert retained.lookup(lightKey(0)).value.bytes.len == 33 and batch.snapshot.bytes ==
      fixture.following.snapshot.bytes, "readers and prepared candidate survive close"
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "prepared candidates retain no lease"
  assert uint64(owner.sequence.value) == 2, "strict reopen after grouped append and compaction"
  assert owner.close == FileError.None
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    var filename = lightChild(path, kind, ManagedEpoch(2))
    assert posix.unlink(filename.toCString()) == 0, "retire exact owned epoch-two fixture"
  retireLightJournal(path)
proc bounded(fixture: LightJournalFixture, changes: openArray[LightJournalEdit],
    mode: int) {.raises.} =
  ## Frame, aggregate bytes, per-frame bytes, nonempty input and sequence capacity all refuse without publication or poison.
  let path = "light-batch-bound-" & $storageProcessId() & "-" & $mode
  var config = fixture.config
  if mode == 0: config.journal.frames = ElementLimit(1)
  elif mode == 1: config.journal.bytes = ByteLimit(98+2*LightDeltaOverhead-1)
  elif mode == 2: config.journal.bytes = ByteLimit(
      98+fixture.next.byteLength+fixture.following.byteLength-1)
  elif mode == 3: config.journal.frame.bytes = ByteLimit(fixture.next.byteLength-1)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert initializeLightJournalCache(owner, path, config, fixture.initial).error == FileError.None
  if mode == 5:
    # A genuine selected maximum-near sequence proves batch addition bounds before preparing any frame.
    assert owner.close == FileError.None
    let selected = prepareLightJournalManifest(fixture.initial, ManagedEpoch(1), LightDeltaSequence(
        high(uint64)-1), ByteLimit(171)).value
    writeFile(path & "/CURRENT", lightText(selected.bytes))
    writeFile(lightChild(path, ManagedFileKind.Journal), lightText(encodeLightJournalAnchor(
        selected, ByteLimit(98)).value))
    assert openLightJournalCache(owner, path, config) == FileError.None
  resetIo()
  resetHash(0)
  let refused = if mode == 4: prepareLightJournalBatch(owner, []) else: prepareLightJournalBatch(
      owner, changes)
  let reason = if mode == 4: FileError.InvalidBatch else: FileError.LimitExceeded
  assert refused.error == reason, "typed bounded batch refusal"
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "bounded preparation performs no IO"
  if mode != 2: assert calls() == 0, "known global or first-frame bounds precede provider work"
  assert owner.preparedSnapshot.value.bytes == fixture.initial.bytes, "bounded refusal preserves confirmed image"
  assert owner.close == FileError.None
  retireLightJournal(path)
proc interrupted(fixture: LightJournalFixture, changes: openArray[LightJournalEdit],
    skip: int) {.raises.} =
  ## A real partial grouped write or failed barrier can leave complete earlier frames; explicit recovery retains exactly that prefix.
  let path = "light-batch-interrupted-" & $storageProcessId() & "-" & $skip
  seedLightJournal(path, fixture)
  var owner = default(LightJournalCache)
  var recovery = default(LightJournalRecovery)
  defer:
    resetIo()
    if recovery.opened: discard recovery.close
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None
  let retained = owner.preparedSnapshot.value
  let batch = prepareLightJournalBatch(owner, changes).value
  let original = readFile(lightChild(path, ManagedFileKind.Journal))
  let frame = lightText(fixture.next.encodedBytes) & lightText(fixture.following.encodedBytes)
  writeFile(path & "/KEEP", "preserve grouped-append sibling")
  resetIo()
  if skip < 0:
    armIo(syncIo, 0, 1, failedIo) # Complete bytes without a confirmed barrier still poison fresh application observations.
  else:
    limitWrites(64)
    armIo(writeIo, cint(skip), 1, failedIo) # Actual native short progress precedes the selected real refusal.
  let expectedReason = if skip < 0: FileError.PublishedUnsynced else: FileError.IoFailure
  assert owner.append(batch).error == expectedReason, "typed uncertain grouped append"
  assert pendingIo() == 0, "consume exact grouped IO refusal"
  assert owner.sequence.error == FileError.RecoveryRequired and owner.snapshot.error ==
      FileError.RecoveryRequired, "uncertainty publishes no fresh final image"
  resetIo()
  let visible = if skip < 0: frame.len else: skip*64
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == original & frame[0..<visible], "exact completed short-write extent"
  assert owner.close == FileError.None
  let completed = if visible == frame.len: 2 elif visible >= fixture.next.byteLength: 1 else: 0
  let partial = visible != 0 and visible != fixture.next.byteLength and visible != frame.len
  let opened = openLightJournalCache(owner, path, fixture.config)
  if partial:
    assert opened == FileError.InvalidJournal and not owner.opened, "strict reopen refuses incomplete grouped suffix"
    assert inspectLightJournalTail(recovery, path, fixture.config) == FileError.None, "explicit grouped-tail inspection"
    assert recovery.plan.value.prefix.frameCount == uint64(completed), "repair retains exactly the complete earlier frames"
    assert recovery.repair(owner).error == FileError.None, "synchronized exact-prefix repair"
  else:
    assert opened == FileError.None, "strict reopen confirms an entirely complete observed prefix"
  assert uint64(owner.sequence.value) == uint64(completed), "exact retained global sequence"
  if completed == 0:
    assert owner.append(batch).error == FileError.None, "original batch remains valid after exact original-prefix recovery"
  else:
    assert owner.append(batch).error == FileError.StaleView, "original batch cannot repeat an already retained frame"
    if completed == 1:
      let remaining = prepareLightJournalBatch(owner, [changes[1]]).value
      assert owner.append(remaining).error == FileError.None, "reprepare only the remaining update at its retained predecessor"
  assert uint64(owner.sequence.value) == 2 and owner.preparedSnapshot.value.bytes ==
      fixture.following.snapshot.bytes, "exact final recovered successor"
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == original & frame, "retry neither duplicates nor drops a completed frame"
  assert retained.bytes == fixture.initial.bytes, "retained old image survives grouped uncertainty"
  assert readFile(path & "/KEEP") == "preserve grouped-append sibling", "recovery preserves unknown sibling"
  assert owner.close == FileError.None
  retireLightJournal(path)
proc main() {.raises.} =
  ## Group related preparation, publication, limit and recovery witnesses around one complete batch feature.
  let fixture = lightFixture()
  let changes = edits(fixture)
  normal(fixture, changes)
  for mode in 0..<6: bounded(fixture, changes, mode)
  let length = fixture.next.byteLength+fixture.following.byteLength
  let chunks = (length+63) div 64
  for skip in 0..<chunks: interrupted(fixture, changes, skip)
  interrupted(fixture, changes, -1)
try:
  main()
except:
  quit(2)
echo "PASS light journal batches: bounded preparation, one barrier, immutable readers, stale positions and exact complete-prefix recovery"
