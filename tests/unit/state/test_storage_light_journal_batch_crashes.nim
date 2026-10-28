# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real process deaths during grouped append preserve exact authenticated prefixes and retry only uncommitted edits.
import std/assertions
import std/envvars
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash
import ../../support/storage_light_journal
import ../../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Observe only exact test-owned paths without scanning or granting selection authority.
proc exists(path: string): bool =
  ## Missing staging is a forensic assertion, independent of any fallback recovery path.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc changes(fixture: LightJournalFixture): array[2, LightJournalEdit] =
  ## Ordinary independently prepared transitions supply borrowed proof transport for a forward/reverse group.
  result = default(array[2, LightJournalEdit])
  let known = fixture.initial.prove(lightKey(0), LightProofReadLimits(entries: ElementLimit(1),
    proof: fixture.config.snapshot.cache.proof)).value
  let absent = fixture.next.snapshot.prove(lightKey(255), LightProofReadLimits(
      entries: ElementLimit(1),
    proof: fixture.config.snapshot.cache.proof)).value
  result[0] = LightJournalEdit(proofs: @[LightStateProof(key: lightKey(255), proof: absent)],
      forgotten: @[lightKey(0)])
  result[1] = LightJournalEdit(proofs: @[LightStateProof(key: lightKey(0), proof: known)],
      forgotten: @[lightKey(255)])
proc prefix(input: string, extent: int): string =
  ## Copy an independently authored bounded prefix without granting any production repair authority.
  assert extent >= 0 and extent <= input.len, "bounded batch forensic prefix"
  result = newString(extent)
  for index in 0..<extent: result[index] = input[index]
proc batchCrash(fixture: LightJournalFixture, previous: bool, operation, skip: cint,
    chunk: int): uint64 {.raises.} =
  ## Every completed control or exact stopped child receives a fresh namespace and independent expected frame bytes.
  let path = "light-batch-crash-" & $storageProcessId() & "-" & $previous & "-" &
    $operation & "-" & $skip & "-" & $chunk
  seedLightJournal(path, fixture)
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  var recovery = default(LightJournalRecovery)
  defer:
    abortCrash()
    resetIo()
    if recovery.opened: discard recovery.close
    if contender.opened: discard contender.close
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "open grouped baseline"
  if previous:
    # A genuine nonempty predecessor journal distinguishes an existing prefix from frames completed inside the new group.
    assert owner.append(fixture.next).error == FileError.None, "seed first predecessor frame"
    assert owner.append(fixture.following).error == FileError.None, "seed second predecessor frame"
  let oldSequence = uint64(owner.sequence.value)
  let oldFrames = oldSequence # This uncompacted fixture starts at zero and commits exactly one frame per sequence.
  let retained = owner.preparedSnapshot.value
  let edits = changes(fixture)
  let first = prepareLightDelta(retained, LightDeltaSequence(oldSequence+1), edits[0].proofs,
    edits[0].forgotten, fixture.config.journal.frame).value
  let second = prepareLightDelta(first.snapshot, LightDeltaSequence(oldSequence+2), edits[1].proofs,
    edits[1].forgotten, fixture.config.journal.frame).value
  let following = prepareLightDelta(second.snapshot, LightDeltaSequence(oldSequence+3), edits[
      0].proofs,
    edits[0].forgotten, fixture.config.journal.frame).value
  let frames = lightText(first.encodedBytes) & lightText(second.encodedBytes)
  let batch = prepareLightJournalBatch(owner, edits).value
  assert batch.byteLength == frames.len and batch.snapshot.encodedBytes ==
      second.snapshot.encodedBytes, "independent batch extent and final image"
  let original = readFile(lightChild(path, ManagedFileKind.Journal))
  let current = readFile(path & "/CURRENT")
  let checkpoint = readFile(lightChild(path, ManagedFileKind.Snapshot))
  assert owner.close == FileError.None, "release parent lease before fork"
  writeFile(path & "/KEEP", "preserve grouped-process sibling")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0, "adopt exact grouped-append child"
  if child == 0:
    # Strict reopen is setup; the observer is armed only around actual prepared append writes and its final barrier.
    if openLightJournalCache(owner, path, fixture.config) != FileError.None: exitCrash(81)
    if chunk > 0: limitWrites(csize_t(chunk))
    if startCrash() != 0: exitCrash(82)
    if owner.append(batch).error != FileError.None: exitCrash(83)
    exitCrash(0)
  if skip != 4096:
    # Completion, stopping and kill/reap are separate witnessed states; a live stopped child must still hold LOCK.
    assert waitCrash() == crashStopped, "exact successful grouped IO stop"
    assert openLightJournalCache(contender, path, fixture.config) == FileError.Busy, "stopped grouped writer holds LOCK"
    assert not contender.opened, "contention grants no parent authority"
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 4096, "positive grouped completion control"
  else:
    assert receipt == crashKilled and result == uint64(skip)+1, "exact grouped stop kill and reap"
  resetIo()
  let written = if operation == writeIo and chunk > 0 and skip != 4096:
    min(frames.len, int(result)*chunk) else: frames.len
  let forensic = original & prefix(frames, written)
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == forensic, "exact authored grouped-write extent"
  assert readFile(path & "/CURRENT") == current, "group append preserves selected manifest"
  assert readFile(lightChild(path, ManagedFileKind.Snapshot)) == checkpoint, "group append preserves checkpoint"
  assert not exists(path & "/CURRENT.next"), "group append creates no staging manifest"
  let complete = if written == frames.len: 2 elif written >= first.byteLength: 1 else: 0
  let kept = if complete == 2: frames.len elif complete == 1: first.byteLength else: 0
  let partial = written != kept
  let opened = openLightJournalCache(owner, path, fixture.config)
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0 and ioCalls(unlinkIo) == 0, "strict grouped reopen changes no forensic bytes"
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == forensic, "strict reopen preserves original interrupted group"
  if partial:
    # Only exact held-inode inspection and synchronized repair may discard the incomplete suffix after authenticated frames.
    assert opened == FileError.InvalidJournal and not owner.opened, "incomplete grouped suffix refuses strict open"
    assert inspectLightJournalTail(recovery, path, fixture.config) == FileError.None, "inspect real killed group"
    let plan = recovery.plan.value
    assert plan.prefix.frameCount == oldFrames+uint64(complete), "retain all predecessor and complete grouped frames"
    assert uint64(plan.prefix.sequence) == oldSequence+uint64(complete), "retain exact authenticated sequence"
    assert plan.prefix.byteLength == original.len+kept, "retain exact authenticated byte extent"
    let image = if complete == 1: first.snapshot else: retained
    assert plan.prefix.snapshot.encodedBytes == image.encodedBytes, "retain exact authenticated image"
    assert recovery.repair(owner).error == FileError.None, "explicit killed-group prefix repair"
    assert readFile(lightChild(path, ManagedFileKind.Journal)) == original & prefix(frames, kept), "repair removes only incomplete frame suffix"
  else:
    # A boundary-aligned complete prefix is already a strict journal, even when later group frames never reached disk.
    assert opened == FileError.None, "complete grouped prefix strictly reopens"
  assert uint64(owner.sequence.value) == oldSequence+uint64(complete), "exact recovered grouped sequence"
  assert owner.journalBytes.value == uint64(original.len+kept), "exact recovered journal extent"
  resetIo()
  if complete == 0:
    assert owner.append(batch).error == FileError.None, "original batch retries only at original predecessor"
  else:
    # Exact starting-position binding prevents duplicating a complete earlier frame from the original prepared group.
    assert owner.append(batch).error == FileError.StaleView, "retained frame makes original group stale"
    assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "stale original group performs no publication IO"
    if complete == 1:
      let remaining = prepareLightJournalBatch(owner, [edits[1]]).value
      assert owner.append(remaining).error == FileError.None, "prepare and append only remaining edit"
  assert uint64(owner.sequence.value) == oldSequence+2, "recovery neither duplicates nor drops sequence"
  assert owner.preparedSnapshot.value.encodedBytes == second.snapshot.encodedBytes, "exact final recovered group image"
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == original & frames, "exact complete group after retry"
  assert owner.append(following).error == FileError.None, "following ordinary frame remains appendable"
  assert uint64(owner.sequence.value) == oldSequence+3, "following update advances exactly once"
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == original & frames & lightText(
      following.encodedBytes), "exact following frame transport"
  assert owner.close == FileError.None, "explicit grouped owner retirement"
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "final strict reopen after recovery and following append"
  assert owner.preparedSnapshot.value.encodedBytes == following.snapshot.encodedBytes, "final strict image matches independent transition"
  assert owner.close == FileError.None, "final native retirement"
  assert retained.encodedBytes == fixture.initial.encodedBytes, "original reader survives real process death and recovery"
  assert retained.cache.lookup(lightKey(0)).value.bytes.len == 33, "original value reader remains present"
  assert readFile(path & "/CURRENT") == current and readFile(lightChild(path,
      ManagedFileKind.Snapshot)) == checkpoint, "recovery and retry preserve checkpoint selection"
  assert readFile(path & "/KEEP") == "preserve grouped-process sibling", "unknown sibling survives group recovery"
  retireLightJournal(path)
proc main() {.raises.} =
  ## Qualify a fresh group and one after two committed frames; aligned chunks witness strict prefix success separately from tail repair.
  let fixture = lightFixture()
  var controls = 0
  var killed = 0
  var aligned = 0
  var chunks = 0
  for previous in [false, true]:
    assert batchCrash(fixture, previous, writeIo, 4096, 0) == 1, "one normal grouped write"
    assert batchCrash(fixture, previous, syncIo, 4096, 0) == 1, "one normal grouped barrier"
    discard batchCrash(fixture, previous, writeIo, 0, 0)
    discard batchCrash(fixture, previous, syncIo, 0, 0)
    controls += 2
    killed += 2
    for limit in [64, fixture.next.byteLength]:
      # Measure real normal completion independently before killing every actual write boundary in its own namespace.
      let count = batchCrash(fixture, previous, writeIo, 4096, limit)
      assert count == uint64((fixture.next.byteLength+fixture.following.byteLength+limit-1) div limit), "actual bounded grouped short-write count"
      assert count > 1 and count < 64, "bounded real short progress"
      assert batchCrash(fixture, previous, syncIo, 4096, limit) == 1, "short-write group completes one final barrier"
      discard batchCrash(fixture, previous, syncIo, 0, limit)
      controls += 2
      killed += int(count)+1
      if limit == 64: chunks += int(count)
      else: aligned += int(count)
      for skip in 0..<int(count):
        discard batchCrash(fixture, previous, writeIo, cint(skip), limit)
  assert controls == 12 and killed == 8+chunks+aligned, "complete grouped crash matrix"
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if directory.len > 0:
    # Numeric evidence is auxiliary; every scenario above already required an actual completion or stopped-child kill receipt.
    writeFile(directory & "/storage_light_journal_batch_crashes.json", "{\"controls\":" &
      $controls &
      ",\"killed_boundaries\":" & $killed & ",\"short_chunks\":" & $chunks &
      ",\"aligned_chunks\":" & $aligned & "}\n")
try:
  main()
except:
  quit(2)
echo "PASS light journal batch crashes: exact grouped boundaries, authenticated prefixes and explicit remaining-edit retry"
