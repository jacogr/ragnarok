# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual stopped-child deaths qualify combined threshold compaction/cleanup and cleanup-only continuation without head fallback.
import std/assertions
import std/envvars
import std/syncio
import ../../support/storage_io
import ../../support/storage_crash
import ../../support/storage_light_root
import ../../support/storage_light_journal
import ../../support/storage_light_maintenance
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../../src/storage/light_journal_manifest as storage_light_journal_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Observe only exact test-owned canonical names; no directory scan creates head or cleanup authority.
proc exists(path: string): bool =
  ## Separate absent staging from an empty canonical prefix.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc prefix(path, authored: string) {.raises.} =
  ## Every candidate that exists must contain only the bounded independently authored transport prefix.
  if exists(path):
    let input = readFile(path)
    assert input.len <= authored.len, "bounded maintenance candidate"
    for index in 0..<input.len: assert input[index] == authored[index], "authored maintenance candidate prefix"
proc writeExtent(path, authored: string, remaining: var int, chunk: int) {.raises.} =
  ## Count successful actual writes independently of production frame/image admission.
  let steps = if chunk == 0: 1 else: (authored.len+chunk-1) div chunk
  let used = min(remaining, steps)
  let extent = if chunk == 0: (if used == 0: 0 else: authored.len) else: min(authored.len, used*chunk)
  if used > 0: assert exists(path) and readFile(path).len == extent, "exact maintenance write extent"
  elif exists(path): assert readFile(path).len == 0, "unwritten candidate is empty"
  remaining -= used
proc captured(path: string): seq[string] {.raises.} =
  ## Snapshot existence and bytes of every known child before strict reopen.
  result = @[]
  for name in ["CURRENT", "CURRENT.next", "LOCK", "KEEP", "snapshot-0000000000000001.bin",
      "journal-0000000000000001.wal", "snapshot-0000000000000002.bin",
      "journal-0000000000000002.wal"]:
    let child = path & "/" & name
    result.add(if exists(child): "present:" & readFile(child) else: "absent")
proc scenario(fixture: LightRootFixture, cleanupOnly: bool, operation, skip: cint,
    chunk: int): uint64 {.raises.} =
  ## Each exact child starts from one confirmed independent-root source with a real preceding ordinary update.
  let path = "maintenance-crash-" & $storageProcessId() & "-" & $cleanupOnly & "-" & $operation &
      "-" & $skip & "-" & $chunk
  let held = seedLightMaintenance(path, fixture, cleanupOnly)
  let selected = prepareLightJournalManifest(held, ManagedEpoch(2), LightDeltaSequence(1),
      ByteLimit(LightJournalManifestBytes)).value
  let targetCurrent = lightText(selected.bytes)
  let anchor = lightText(encodeLightJournalAnchor(selected, fixture.oldConfig.journal.bytes).value)
  let image = lightText(held.encodedBytes)
  let oldSelected = prepareLightJournalManifest(fixture.source, ManagedEpoch(1), LightDeltaSequence(
      0), ByteLimit(LightJournalManifestBytes)).value
  let oldCurrent = lightText(oldSelected.bytes)
  let oldImage = readFile(lightChild(path, ManagedFileKind.Snapshot))
  let oldLog = readFile(lightChild(path, ManagedFileKind.Journal))
  let targetImage = lightChild(path, ManagedFileKind.Snapshot, ManagedEpoch(2))
  let targetLog = lightChild(path, ManagedFileKind.Journal, ManagedEpoch(2))
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  defer:
    abortCrash()
    resetIo()
    if contender.opened: discard contender.close
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  let plan = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
      maintenanceLimits()).value
  assert plan.compactionNeeded == not cleanupOnly and uint64(plan.retiredCount) == 1
  assert owner.close == FileError.None
  writeFile(path & "/KEEP", "preserve maintenance sibling")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0, "adopt exact maintenance child"
  if child == 0:
    # Reopen precedes arming; only real maintenance operations can supply stop/completion receipts.
    if openLightJournalCache(owner, path, fixture.oldConfig) != FileError.None: exitCrash(81)
    if chunk > 0: limitWrites(csize_t(chunk))
    if startCrash() != 0: exitCrash(82)
    let receipt = owner.maintain(plan)
    if receipt.error != FileError.None: exitCrash(83)
    if receipt.value.retirement != FileError.None or receipt.value.cleanup !=
        FileError.None: exitCrash(84)
    exitCrash(0)
  if skip != 4096:
    assert waitCrash() == crashStopped, "exact successful maintenance IO stop"
    assert openLightJournalCache(contender, path, fixture.oldConfig) == FileError.Busy and
        not contender.opened, "stopped maintenance retains directory LOCK"
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 4096, "real maintenance completion control"
  else:
    assert receipt == crashKilled and result == uint64(skip)+1, "exact stop kill and reap receipt"
  resetIo()
  let current = readFile(path & "/CURRENT")
  let newSelected = current == targetCurrent
  assert current == oldCurrent or newSelected, "only exact independently authored CURRENT selection"
  if cleanupOnly: assert newSelected, "cleanup cannot change selected epoch"
  if exists(lightChild(path, ManagedFileKind.Journal)):
    assert readFile(lightChild(path, ManagedFileKind.Journal)) == oldLog
    assert exists(lightChild(path, ManagedFileKind.Snapshot)), "retired journal removed before retired checkpoint"
  if exists(lightChild(path, ManagedFileKind.Snapshot)):
    assert readFile(lightChild(path, ManagedFileKind.Snapshot)) == oldImage
  if not newSelected:
    assert readFile(lightChild(path, ManagedFileKind.Snapshot)) == oldImage and readFile(lightChild(
        path, ManagedFileKind.Journal)) == oldLog, "unselected compaction preserves source pair"
  prefix(targetImage, image)
  prefix(targetLog, anchor)
  prefix(path & "/CURRENT.next", targetCurrent)
  if not cleanupOnly and operation == writeIo and skip != 4096:
    # A successful write stop precedes rename; every completed chunk belongs to one exact checkpoint/anchor/manifest extent.
    assert not newSelected
    var remaining = int(result)
    writeExtent(targetImage, image, remaining, chunk)
    writeExtent(targetLog, anchor, remaining, chunk)
    writeExtent(path & "/CURRENT.next", targetCurrent, remaining, chunk)
    assert remaining == 0, "every successful write accounted for"
  elif not cleanupOnly:
    # Non-write stops occur only between complete transport writes; partially sized candidates would be unexplained.
    if exists(targetImage): assert readFile(targetImage) == image
    if exists(targetLog): assert readFile(targetLog) == anchor
    if exists(path & "/CURRENT.next"): assert readFile(path & "/CURRENT.next") == targetCurrent
  if newSelected:
    assert readFile(targetImage) == image and readFile(targetLog) == anchor and not exists(path &
        "/CURRENT.next"), "selected compaction is complete before old cleanup"
  assert not exists(lightChild(path, ManagedFileKind.Snapshot, ManagedEpoch(3))) and not exists(
      lightChild(path, ManagedFileKind.Journal, ManagedEpoch(3))), "maintenance never scans or writes a future epoch"
  let before = captured(path)
  resetIo()
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None, "strict exact-root reopen after killed maintenance"
  assert captured(path) == before and ioCalls(writeIo) == 0 and ioCalls(
      unlinkIo) == 0 and ioCalls(renameIo) == 0, "strict reopen preserves all forensic bytes"
  assert uint64(owner.epoch.value) == (if newSelected: 2'u64 else: 1'u64) and uint64(
      owner.sequence.value) == 1
  if not newSelected:
    assert owner.discardUnselectedMaintenance(plan) == FileError.None, "explicit matching unselected candidate discard"
    assert owner.maintain(plan).value.cleanup == FileError.None, "exact original source retries after guarded discard"
  else:
    # An old compaction decision cannot run again; a fresh cleanup-only decision retries any interrupted old-pair job.
    if not cleanupOnly:
      assert owner.maintain(plan).error == FileError.StaleView
      assert owner.discardUnselectedMaintenance(plan) == FileError.InvalidRetention
    let fresh = prepareLightMaintenance(owner, owner.epoch.value, owner.sequence.value,
        maintenanceLimits()).value
    assert not fresh.compactionNeeded and uint64(fresh.retiredCount) == 1
    resetIo()
    let retried = owner.maintain(fresh).value
    assert retried.cleanup == FileError.None and uint64(retried.retired) == 1 and uint64(
        retried.nextRetiredEpoch) == 2
    assert ioCalls(syncIo) > 0, "already absent cleanup names still synchronize"
  assert readFile(path & "/CURRENT") == targetCurrent and readFile(targetImage) == image and
      readFile(targetLog) == anchor
  let retention = LightRetentionLimits(items: ElementLimit(3), valueBytes: ByteLimit(128),
      bytes: ByteLimit(8192), entries: ElementLimit(3), evictions: ElementLimit(1))
  assert owner.admitRetained([fixture.sourceProofs[1]], retention).error == FileError.None, "following retained admission after maintenance recovery"
  assert uint64(owner.sequence.value) == 2 and owner.snapshot.value.lookup(lightKey(
      32)).value.bytes[0] == 11
  assert held.cache.lookup(lightKey(0)).value.bytes[0] == 7, "old image reader survives physical cleanup and child death"
  assert readFile(path & "/KEEP") == "preserve maintenance sibling"
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None and uint64(
      owner.sequence.value) == 2
  assert owner.close == FileError.None
  retireRootEpoch(path, ManagedEpoch(2))
  retireLightJournal(path)
proc main() {.raises.} =
  ## Measure positive controls first, then kill every actual boundary for combined and cleanup-only maintenance.
  let fixture = rootFixture()
  let image = fixture.source.forget([lightKey(32)]).value
  var controls = 0
  var killed = 0
  var shortWrites = 0
  for cleanupOnly in [false, true]:
    let operations = if cleanupOnly: @[syncIo, unlinkIo, closeIo] else: @[writeIo, syncIo, renameIo,
        unlinkIo, closeIo]
    for operation in operations:
      let count = scenario(fixture, cleanupOnly, operation, 4096, 0)
      assert count > 0 and count < 32, "bounded observed maintenance syscall matrix"
      let expected = if operation == syncIo: (if cleanupOnly: 3 else: 11)
        elif operation == unlinkIo: 2
        elif operation == writeIo: 3
        elif operation == renameIo: 1
        else: (if cleanupOnly: 6 else: 10)
      assert count == uint64(expected), "independent maintenance counts: " & $cleanupOnly & ":" &
          $operation & " actual=" & $count & " expected=" & $expected
      controls += 1
      for skip in 0..<int(count):
        discard scenario(fixture, cleanupOnly, operation, cint(skip), 0)
        killed += 1
    if not cleanupOnly:
      # Genuine 64-byte progress reaches partial checkpoint, anchor and pending manifest states separately.
      let count = scenario(fixture, false, writeIo, 4096, 64)
      let expected = (image.byteLength+63) div 64 + (LightJournalAnchorBytes+63) div 64 + (
          LightJournalManifestBytes+63) div 64
      assert count == uint64(expected) and count > 3 and count < 64
      controls += 1
      shortWrites = int(count)
      for skip in 0..<int(count):
        discard scenario(fixture, false, writeIo, cint(skip), 64)
        killed += 1
  let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
  if evidence.len > 0:
    let counts = "{\"controls\":" & $controls & ",\"killed_boundaries\":" & $killed &
        ",\"short_write_boundaries\":" & $shortWrites & "}\n"
    writeFile(evidence & "/storage_light_maintenance_crashes.json", counts)
try:
  main()
except:
  quit(2)
echo "PASS light maintenance crashes: exact compaction/cleanup deaths, guarded candidate discard and bounded fresh-plan continuation"
