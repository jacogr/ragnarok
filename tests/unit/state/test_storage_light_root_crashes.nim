# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact stopped-child deaths qualify root selection and both cleanup paths against independent authored old/new-root bytes.
import std/assertions
import std/envvars
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash
import ../../support/storage_light_journal
import ../../support/storage_light_root
import ../../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../../src/storage/light_journal_manifest as storage_light_journal_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Only exact test-owned names are observed; directory scans never establish selection authority.
proc exists(path: string): bool =
  ## Distinguish absent candidates from empty authored prefixes before any reopen.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc captured(path: string): seq[string] {.raises.} =
  ## Preserve existence as well as every byte of all known children during strict wrong-root refusal.
  result = @[]
  for name in ["CURRENT", "CURRENT.next", "LOCK", "KEEP",
      "snapshot-0000000000000001.bin", "journal-0000000000000001.wal",
      "snapshot-0000000000000002.bin", "journal-0000000000000002.wal"]:
    let child = path & "/" & name
    result.add(if exists(child): "present:" & readFile(child) else: "absent")
proc authoredPrefix(path, authored: string) {.raises.} =
  ## An unselected candidate may be absent or an exact bounded prefix, never foreign or overlong bytes.
  if exists(path):
    let input = readFile(path)
    assert input.len <= authored.len, "candidate extent bounded by authored transport"
    for index in 0..<input.len:
      assert input[index] == authored[index], "candidate contains only authored prefix bytes"
proc writeExtent(path, authored: string, calls: var int, chunk: int) {.raises.} =
  ## Independently account for every successful real write, including chunks that end at file boundaries.
  let steps = if chunk == 0: 1 else: (authored.len+chunk-1) div chunk
  let used = min(calls, steps)
  let extent = if chunk == 0: (if used == 1: authored.len else: 0) else: min(authored.len, used*chunk)
  if used > 0:
    assert exists(path) and readFile(path).len == extent, "exact successful-write extent"
  elif exists(path):
    assert readFile(path).len == 0, "unwritten candidate can only be empty"
  calls -= used
proc scenario(fixture: LightRootFixture, mode: int, operation, skip: cint,
    chunk: int): uint64 {.raises.} =
  ## Each selection, candidate cleanup or retired cleanup control uses a fresh real namespace and exact child lease.
  let path = "light-root-crash-" & $storageProcessId() & "-" & $mode & "-" &
    $operation & "-" & $skip & "-" & $chunk
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  defer:
    abortCrash()
    resetIo()
    if contender.opened: discard contender.close
    if owner.opened: discard owner.close
  assert initializeLightJournalCache(owner, path, fixture.oldConfig, fixture.source).error == FileError.None
  let predecessor = prepareLightDelta(fixture.source, LightDeltaSequence(1), [], [lightKey(32)],
    fixture.oldConfig.journal.frame).value
  assert owner.append(predecessor).error == FileError.None, "nonzero source sequence before root selection"
  let retained = owner.preparedSnapshot.value
  let plan = prepareLightRootAdvance(owner, ManagedEpoch(1), LightDeltaSequence(1),
    fixture.newConfig.root, fixture.destination).value
  let target = prepareLightJournalManifest(fixture.destination, ManagedEpoch(2),
    LightDeltaSequence(1), ByteLimit(LightJournalManifestBytes)).value
  let anchor = lightText(encodeLightJournalAnchor(target, fixture.newConfig.journal.bytes).value)
  let manifest = lightText(target.bytes)
  let image = lightText(fixture.destination.encodedBytes)
  let oldCurrent = readFile(path & "/CURRENT")
  let oldImage = readFile(lightChild(path, ManagedFileKind.Snapshot))
  let oldLog = readFile(lightChild(path, ManagedFileKind.Journal))
  let targetImage = lightChild(path, ManagedFileKind.Snapshot, ManagedEpoch(2))
  let targetLog = lightChild(path, ManagedFileKind.Journal, ManagedEpoch(2))
  if mode == 1:
    # A real failed second pending-manifest chunk leaves all three candidates with exact authored bytes.
    resetIo()
    limitWrites(64)
    let beforePending = (image.len+63) div 64 + (anchor.len+63) div 64
    armIo(writeIo, cint(beforePending+1), 1, failedIo)
    assert owner.advanceRoot(plan).error == FileError.IoFailure and pendingIo() == 0
    resetIo()
    assert readFile(path & "/CURRENT") == oldCurrent, "partial pending manifest never selects root"
    assert readFile(targetImage) == image and readFile(targetLog) == anchor
    assert readFile(path & "/CURRENT.next").len == 64, "real partial pending manifest"
  elif mode == 2:
    # Retired-source cleanup starts only after confirmed selection of the independently accepted new root.
    assert owner.advanceRoot(plan).error == FileError.None
  assert owner.close == FileError.None, "parent releases lease before fork"
  writeFile(path & "/KEEP", "preserve root-crash sibling")
  let config = if mode == 2: fixture.newConfig else: fixture.oldConfig
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0, "adopt exact root-operation child"
  if child == 0:
    # Reopen is setup; arm only around the selected durable operation, never around fixture construction.
    if openLightJournalCache(owner, path, config) != FileError.None: exitCrash(81)
    if chunk > 0: limitWrites(csize_t(chunk))
    if startCrash() != 0: exitCrash(82)
    let reason = if mode == 0: owner.advanceRoot(plan).error
      elif mode == 1: owner.discardUnselectedRootAdvance(plan)
      else: owner.cleanupRetiredEpoch(ManagedEpoch(1))
    if reason != FileError.None: exitCrash(83)
    exitCrash(0)
  if skip != 4096:
    # Even after old append-handle retirement, a stopped root publisher still owns the directory LOCK lease.
    assert waitCrash() == crashStopped, "successful exact IO stop"
    assert openLightJournalCache(contender, path, config) == FileError.Busy
    assert not contender.opened, "stopped-child contention grants no owner"
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 4096, "explicit positive completion receipt"
  else:
    assert receipt == crashKilled and result == uint64(skip)+1, "exact stopped-child kill and reap receipt"
  resetIo()
  let selected = readFile(path & "/CURRENT")
  assert selected == oldCurrent or selected == manifest, "selection equals exactly one independently authored manifest"
  let newSelected = selected == manifest
  assert (mode != 1 or not newSelected) and (mode != 2 or newSelected)
  if mode != 2:
    assert readFile(lightChild(path, ManagedFileKind.Snapshot)) == oldImage
    assert readFile(lightChild(path, ManagedFileKind.Journal)) == oldLog
  else:
    # Interrupted old-root deletion may remove either exact old child, without changing selected-root files.
    authoredPrefix(lightChild(path, ManagedFileKind.Snapshot), oldImage)
    authoredPrefix(lightChild(path, ManagedFileKind.Journal), oldLog)
    for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
      let name = lightChild(path, kind)
      if exists(name): assert readFile(name) == (if kind ==
          ManagedFileKind.Snapshot: oldImage else: oldLog)
  authoredPrefix(targetImage, image)
  authoredPrefix(targetLog, anchor)
  authoredPrefix(path & "/CURRENT.next", manifest)
  if mode == 0 and operation == writeIo and skip != 4096:
    # Successful writes precede rename; calculate exact per-file extent independently of CURRENT decoding.
    assert not newSelected, "write stop precedes manifest rename"
    var remaining = int(result)
    writeExtent(targetImage, image, remaining, chunk)
    writeExtent(targetLog, anchor, remaining, chunk)
    writeExtent(path & "/CURRENT.next", manifest, remaining, chunk)
    assert remaining == 0, "all witnessed writes accounted for"
  if mode == 1:
    # Cleanup only unlinks; any surviving child must retain its complete pre-cleanup bytes and removal order.
    if exists(targetImage): assert readFile(targetImage) == image
    if exists(targetLog): assert readFile(targetLog) == anchor and exists(targetImage)
    if exists(path & "/CURRENT.next"):
      assert readFile(path & "/CURRENT.next").len == 64 and exists(targetLog)
  elif mode == 2:
    # Retired cleanup removes the old journal before its checkpoint; neither path can be rewritten.
    assert not exists(path & "/CURRENT.next")
    if exists(lightChild(path, ManagedFileKind.Journal)):
      assert exists(lightChild(path, ManagedFileKind.Snapshot))
  elif operation != writeIo:
    # Every non-write stop occurs between whole transport writes, so no partial file extent is admissible.
    if exists(targetImage): assert readFile(targetImage) == image
    if exists(targetLog): assert readFile(targetLog) == anchor
    if exists(path & "/CURRENT.next"): assert readFile(path & "/CURRENT.next") == manifest
  if newSelected:
    assert readFile(targetImage) == image and readFile(targetLog) == anchor
    assert not exists(path & "/CURRENT.next"), "renamed manifest has no pending sibling"
  let beforeOpen = captured(path)
  let wrong = if newSelected: fixture.oldConfig else: fixture.newConfig
  assert openLightJournalCache(owner, path, wrong) == FileError.WrongIdentity and not owner.opened
  assert captured(path) == beforeOpen, "wrong independently expected root preserves forensic bytes"
  let expected = if newSelected: fixture.newConfig else: fixture.oldConfig
  assert openLightJournalCache(owner, path, expected) == FileError.None
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0 and ioCalls(unlinkIo) == 0, "strict reopen performs no repair or fallback"
  assert captured(path) == beforeOpen, "correct strict reopen preserves forensic bytes"
  assert uint64(owner.sequence.value) == 1, "crash cannot advance ordinary-update sequence"
  if not newSelected:
    # Explicit exact-plan cleanup remains retryable even after every candidate unlink already completed before death.
    resetIo()
    assert owner.discardUnselectedRootAdvance(plan) == FileError.None
    assert ioCalls(syncIo) > 0, "cleanup retry synchronizes even absent candidates"
    assert not exists(targetImage) and not exists(targetLog) and not exists(path & "/CURRENT.next")
    assert owner.advanceRoot(plan).error == FileError.None, "original exact source plan remains publishable"
  else:
    assert owner.advanceRoot(plan).error == FileError.StaleView
    assert owner.discardUnselectedRootAdvance(plan) == FileError.InvalidRetention, "selected destination cannot be discarded"
  assert owner.preparedSnapshot.value.encodedBytes == fixture.destination.encodedBytes
  let cache = owner.snapshot.value
  assert cache.lookup(lightKey(0)).value.bytes[0] == 9
  assert cache.lookup(lightKey(64)).value.bytes.len == 0, "new-root present-empty evidence"
  assert cache.lookup(lightKey(128)).value.kind == StateLookupKind.Absent
  assert cache.lookup(lightKey(32)).error == LightCacheError.UnknownKey
  assert cache.lookup(lightKey(255)).error == LightCacheError.UnknownKey, "old negative evidence never carries into destination"
  resetIo()
  assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert ioCalls(syncIo) > 0, "retired cleanup retry synchronizes even absent old files"
  assert readFile(path & "/CURRENT") == manifest and readFile(targetImage) == image and readFile(
      targetLog) == anchor
  let following = prepareLightDelta(fixture.destination, LightDeltaSequence(2), [fixture.following],
      [],
    fixture.newConfig.journal.frame).value
  assert owner.append(following).error == FileError.None, "new-root ordinary update works after crash recovery"
  assert uint64(owner.sequence.value) == 2 and owner.preparedSnapshot.value.encodedBytes ==
      following.snapshot.encodedBytes
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.newConfig) == FileError.None
  assert owner.preparedSnapshot.value.encodedBytes == following.snapshot.encodedBytes
  assert owner.close == FileError.None
  assert retained.encodedBytes == predecessor.snapshot.encodedBytes and retained.cache.lookup(
      lightKey(0)).value.bytes[0] == 7
  assert retained.cache.lookup(lightKey(255)).value.kind == StateLookupKind.Absent, "held old-root reader survives cleanup and process deaths"
  assert readFile(path & "/KEEP") == "preserve root-crash sibling"
  retireRootEpoch(path, ManagedEpoch(2))
  retireLightJournal(path)
proc main() {.raises.} =
  ## Measure every operation independently with a completion control, then kill every actually witnessed successful boundary.
  let fixture = rootFixture()
  var controls = 0
  var killed = 0
  var shortWrites = 0
  for mode in 0..2:
    let operations = if mode == 0: @[writeIo, syncIo, renameIo, closeIo] else: @[unlinkIo, syncIo]
    for operation in operations:
      let count = scenario(fixture, mode, operation, 4096, 0)
      assert count < 64, "bounded root-operation syscall matrix"
      let expected = if mode == 0:
        (if operation == writeIo: 3 elif operation == syncIo: 8 elif operation ==
            renameIo: 1 else: 4)
        elif mode == 1: (if operation == unlinkIo: 3 else: 4)
        else: (if operation == unlinkIo: 2 else: 3)
      assert count == uint64(expected), "independent normal-operation boundary counts"
      controls += 1
      for skip in 0..<int(count):
        discard scenario(fixture, mode, operation, cint(skip), 0)
        killed += 1
    if mode == 0:
      # Real bounded writes qualify partial checkpoint, anchor and pending-manifest progress at every chunk boundary.
      let count = scenario(fixture, mode, writeIo, 4096, 64)
      let expected = (fixture.destination.byteLength+63) div 64 +
        (LightJournalAnchorBytes+63) div 64 + (LightJournalManifestBytes+63) div 64
      assert count == uint64(expected) and count > 3 and count < 128
      controls += 1
      shortWrites = int(count)
      for skip in 0..<int(count):
        discard scenario(fixture, mode, writeIo, cint(skip), 64)
        killed += 1
  assert controls == 9 and killed > shortWrites, "complete root-selection and cleanup matrix"
  let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
  if evidence.len > 0:
    # Auxiliary numeric evidence records actual receipts; the assertions above own every success verdict.
    writeFile(evidence & "/storage_light_root_crashes.json", "{\"controls\":" & $controls &
      ",\"killed_boundaries\":" & $killed & ",\"short_write_boundaries\":" & $shortWrites & "}\n")
try:
  main()
except:
  quit(2)
echo "PASS light root crashes: exact selection and cleanup deaths, strict expected-root reopen and retained readers"
