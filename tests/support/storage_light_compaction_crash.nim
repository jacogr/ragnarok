# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real process stops qualify compaction selection and both cleanup paths against exact authored file bytes.
import std/[assertions, syncio]
import std/posix/posix
import ./[storage_io, storage_crash, storage_light_journal]
import ../../src/storage/light/journal/[cache as light_journal_cache,
    manifest as light_journal_manifest, replay as light_journal_replay]
import ../../src/storage/light/[delta as light_delta, snapshot as light_snapshot]
import ../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../src/storage/file/errors as file_errors
import ../../src/codec/bounded
type LightReplacementAction* = enum ## One coherent namespace transition is observed after its setup completes.
  ReplaceCheckpoint, RetirePrevious, DiscardCandidate
proc accessNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Observe exact fixture presence through the supported platform ABI.
proc exists(path: string): bool =
  ## Inspect only known owned fixture names; directory contents never establish selection.
  var name = path
  accessNative(name.toCString(), 0) == 0
proc checkPrefix(input, expected: string) =
  ## Incomplete unselected output must be an exact authored prefix with no invented padding.
  assert input.len <= expected.len, "candidate extent bounded by authored bytes"
  for index in 0..<input.len: assert input[index] == expected[index], "exact candidate prefix"
proc lightReplacementCrash*(fixture: LightJournalFixture, action: LightReplacementAction,
    operation, skip: cint, shortWrites = false): uint64 {.raises.} =
  ## Every killed boundary preserves the old/new selected image and permits a fresh explicit cleanup/retry.
  let path = "light-replacement-crash-" & $storageProcessId() & "-" & $action & "-" &
      $operation & "-" & $skip & "-" & $shortWrites
  seedLightJournal(path, fixture)
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  defer:
    abortCrash()
    resetIo()
    if contender.opened: discard contender.close
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "open replacement baseline"
  assert owner.append(fixture.next).error == FileError.None, "establish nonempty old journal"
  let retained = owner.preparedSnapshot.value
  let prepared = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(1)).value
  let selected = prepareLightJournalManifest(retained, ManagedEpoch(2), LightDeltaSequence(1),
      ByteLimit(LightJournalManifestBytes)).value
  let newManifest = lightText(selected.bytes)
  let newAnchor = lightText(encodeLightJournalAnchor(selected, ByteLimit(
      LightJournalAnchorBytes)).value)
  let newSnapshot = lightText(retained.encodedBytes)
  let oldCurrent = readFile(path & "/CURRENT")
  let oldSnapshot = readFile(lightChild(path, ManagedFileKind.Snapshot))
  let oldJournal = readFile(lightChild(path, ManagedFileKind.Journal))
  if action == RetirePrevious:
    # Cleanup starts only after an independently confirmed new checkpoint selection.
    assert owner.compact(prepared).error == FileError.None, "confirm epoch two before retirement"
  elif action == DiscardCandidate:
    # Real rename refusal leaves a complete unselected checkpoint, anchor and staged manifest.
    resetIo()
    armIo(renameIo, 0, 1, failedIo)
    assert owner.compact(prepared).error == FileError.IoFailure, "leave an actual abandoned candidate"
    assert pendingIo() == 0, "consume candidate staging refusal"
    resetIo()
  assert owner.close == FileError.None, "release parent lease before fork"
  writeFile(path & "/KEEP", "preserve independent sibling")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0, "adopt exactly one owned child"
  if child == 0:
    # Exclude strict setup and preparation from the observed mutation boundary.
    if openLightJournalCache(owner, path, fixture.config) != FileError.None: exitCrash(81)
    if shortWrites: limitWrites(64)
    if startCrash() != 0: exitCrash(82)
    case action
    of ReplaceCheckpoint:
      if owner.compact(prepared).error != FileError.None: exitCrash(83)
    of RetirePrevious:
      if owner.cleanupRetiredEpoch(ManagedEpoch(1)) != FileError.None: exitCrash(84)
    of DiscardCandidate:
      if owner.discardUnselectedCompaction(prepared) != FileError.None: exitCrash(85)
    exitCrash(0)
  if skip != 4096:
    # Check live lease contention while the exact child still owns its witnessed stop.
    assert waitCrash() == crashStopped, "matching native successful-operation stop"
    assert openLightJournalCache(contender, path, fixture.config) == FileError.Busy, "stopped child retains lease"
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 128, "bounded completed control"
  else:
    assert receipt == crashKilled and result == uint64(skip)+1, "exact successful stop kill and reap"
  resetIo()
  let names = ["CURRENT", "CURRENT.next", "snapshot-0000000000000001.bin",
    "journal-0000000000000001.wal", "snapshot-0000000000000002.bin", "journal-0000000000000002.wal"]
  var present = default(array[6, bool])
  var forensic = default(array[6, string])
  for index in 0..<names.len:
    # Capture every known name before strict reopen; no successful or refused read may clean it.
    present[index] = exists(path & "/" & names[index])
    if present[index]: forensic[index] = readFile(path & "/" & names[index])
  assert present[0], "replacement always retains a selected manifest"
  let replaced = forensic[0] == newManifest
  assert replaced or forensic[0] == oldCurrent, "CURRENT is exactly old or new"
  if present[1]: checkPrefix(forensic[1], newManifest)
  if present[2]: assert forensic[2] == oldSnapshot, "old checkpoint bytes never change"
  if present[3]: assert forensic[3] == oldJournal, "old journal bytes never change"
  if present[4]: checkPrefix(forensic[4], newSnapshot)
  if present[5]: checkPrefix(forensic[5], newAnchor)
  if replaced:
    # Renamed selection cannot precede complete checkpoint and anchor output.
    assert present[4] and forensic[4] == newSnapshot, "selected new checkpoint is complete"
    assert present[5] and forensic[5] == newAnchor, "selected new anchor is complete"
    assert not present[1], "selection consumed staged manifest"
  else:
    assert present[2] and present[3], "old selected files retained"
  if action == ReplaceCheckpoint:
    assert present[2] and present[3], "compaction retains both old files at every boundary"
    if operation == writeIo and skip != 4096:
      # Predict actual file extents from global completed write count, including genuine short native chunks.
      let chunk = if shortWrites: 64 else: 4096
      let payloads = [newSnapshot, newAnchor, newManifest]
      let positions = [4, 5, 1]
      var remaining = int(result)
      for index in 0..<payloads.len:
        let count = min(remaining, (payloads[index].len+chunk-1) div chunk)
        remaining -= count
        assert present[positions[index]] == (count > 0), "future output not created before its first write"
        if count > 0:
          assert forensic[positions[index]].len == min(payloads[index].len, count*chunk), "exact completed output extent"
      assert remaining == 0 and not replaced, "write stops precede selection"
  elif action == RetirePrevious:
    assert replaced, "retired cleanup never changes current selection"
    assert present[2] or not present[3], "old journal is removed before old checkpoint"
  else:
    assert not replaced, "candidate cleanup never selects its output"
    assert not present[1] or (present[4] and present[5]), "staged candidate is removed first"
    assert present[4] or not present[5], "candidate journal is removed before checkpoint"
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "strict reopen confirms exact old or new selection"
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0 and ioCalls(unlinkIo) == 0, "strict reopen preserves forensic namespace"
  for index in 0..<names.len:
    assert exists(path & "/" & names[index]) == present[index], "strict reopen preserves exact presence"
    if present[index]: assert readFile(path & "/" & names[index]) == forensic[index], "strict reopen preserves exact bytes"
  assert owner.preparedSnapshot.value.bytes == retained.bytes, "replacement and cleanup preserve proof knowledge"
  assert uint64(owner.sequence.value) == 1, "replacement preserves global sequence"
  if replaced:
    # Retry completes directory durability even when both retired files were already absent at death.
    assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "explicit retired cleanup retry"
  else:
    assert owner.discardUnselectedCompaction(prepared) == FileError.None, "explicit candidate cleanup retry"
    assert owner.compact(prepared).error == FileError.None, "same prepared candidate can publish after cleanup"
    assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "retire old files after confirmed retry"
  assert not exists(lightChild(path, ManagedFileKind.Snapshot)), "retired checkpoint absent after retry"
  assert not exists(lightChild(path, ManagedFileKind.Journal)), "retired journal absent after retry"
  assert not exists(path & "/CURRENT.next"), "staging absent after retry"
  assert uint64(owner.epoch.value) == 2, "one physical epoch advance"
  assert owner.append(fixture.following).error == FileError.None, "following global frame remains appendable"
  assert owner.close == FileError.None, "retire parent before strict final reopen"
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "strict reopen after following append"
  assert uint64(owner.sequence.value) == 2 and owner.preparedSnapshot.value.bytes ==
      fixture.following.snapshot.bytes, "exact following successor"
  assert owner.close == FileError.None, "explicit final owner retirement"
  assert retained.bytes == fixture.next.snapshot.bytes, "old immutable reader survives every namespace transition"
  assert readFile(path & "/KEEP") == "preserve independent sibling", "unknown sibling preserved"
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    var file = lightChild(path, kind, ManagedEpoch(2))
    assert posix.unlink(file.toCString()) == 0, "retire exact owned epoch-two fixture"
  retireLightJournal(path)
