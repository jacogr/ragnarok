# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit held-inode repair refuses stale transport/selection, synchronizes only authenticated prefixes and transfers one lease.
# @@Verification={"arc":"storage_light_journal_repair_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io, storage_crash, storage_light_journal]
import ../../../src/storage/light/journal/[cache as light_journal_cache,
    replay as light_journal_replay, manifest as light_journal_manifest]
import ../../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../../src/storage/file/errors as file_errors
import ../../../src/storage/durability
import ../../../src/codec/bounded
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Revalidation provider refusal must never reach truncate or transfer writable authority.
proc renameFile(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Test-only deliberate selected-path substitution proves equal bytes cannot replace held inode identity.
proc path(suffix: string): string =
  ## Hastur already supplies an ignored isolated work directory with an existing parent.
  "light-journal-repair-" & $storageProcessId() & "-" & suffix
proc first(input: string, size: int): string =
  ## Copy a proved prefix for exact malformed/truncated fixture observations.
  assert size >= 0 and size <= input.len, "repair witness 21"
  result = newString(size)
  for index in 0..<size: result[index] = input[index]
proc inspected(path: string, fixture: LightJournalFixture) =
  ## Retire all temporary recovery image/plan/lease ownership before ARC sampling.
  var recovery = default(LightJournalRecovery)
  assert inspectLightJournalTail(recovery, path, fixture.config) == FileError.None, "repair witness 27"
  let retained = recovery.plan.value
  assert retained.prefix.snapshot.bytes == fixture.initial.bytes, "repair witness 29"
  assert recovery.close == FileError.None, "repair witness 30"
  assert retained.prefix.byteLength == LightJournalAnchorBytes, "repair witness 31"
proc normal(fixture: LightJournalFixture) {.raises.} =
  ## One explicit repair truncates only the authenticated prefix, retains forensic siblings and transfers the exact native lease.
  let directory = path("normal")
  seedLightJournal(directory, fixture, true)
  writeFile(directory & "/KEEP", "forensic sentinel")
  let current = readFile(directory & "/CURRENT")
  let checkpoint = readFile(lightChild(directory, ManagedFileKind.Snapshot))
  let partial = readFile(lightChild(directory, ManagedFileKind.Journal))
  assert partial.len == LightJournalAnchorBytes+64, "repair witness 40"
  var recovery = default(LightJournalRecovery)
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  defer:
    resetIo()
    if recovery.opened: discard recovery.close
    if owner.opened: discard owner.close
    if contender.opened: discard contender.close
  assert recovery.close == FileError.Uninitialized and recovery.plan.error ==
      FileError.Uninitialized, "repair witness 49"
  assert recovery.repair(owner).error == FileError.Uninitialized, "repair witness 51"
  assert openLightJournalCache(owner, directory, fixture.config) == FileError.InvalidJournal, "repair witness 52"
  assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.None, "repair witness 53"
  let retained = recovery.plan.value
  assert retained.totalBytes == partial.len and retained.prefix.byteLength ==
      LightJournalAnchorBytes, "repair witness 55"
  assert openLightJournalCache(contender, directory, fixture.config) == FileError.Busy, "repair witness 56"
  assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.Busy, "repair witness 57"
  let busyDirectory = path("busy-target")
  seedLightJournal(busyDirectory, fixture)
  assert openLightJournalCache(owner, busyDirectory, fixture.config) == FileError.None, "live transfer target"
  resetIo()
  assert recovery.repair(owner).error == FileError.Busy, "repair does not overwrite an existing owner"
  assert ioCalls(truncateIo) == 0 and ioCalls(writeIo) == 0, "busy target does no destructive IO"
  assert owner.close == FileError.None and recovery.plan.error == FileError.None, "busy target leaves the inspection valid"
  retireLightJournal(busyDirectory)
  var moved = move(recovery)
  assert not recovery.opened and moved.opened, "repair witness 59"
  resetIo()
  limitReads(7)
  assert moved.repair(owner).value == StorageDurability.FileAndDirectorySynced, "repair witness 62"
  assert not moved.opened and owner.opened and recovery.plan.error == FileError.Uninitialized, "repair witness 63"
  assert ioCalls(truncateIo) == 1 and ioCalls(syncIo) == 2, "repair witness 64"
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0 and ioCalls(readIo) > 2, "repair witness 65"
  resetIo()
  assert owner.preparedSnapshot.value.bytes == fixture.initial.bytes and uint64(
      owner.sequence.value) == 0, "repair witness 67"
  assert owner.journalBytes.value == uint64(LightJournalAnchorBytes), "repair witness 69"
  assert readFile(lightChild(directory, ManagedFileKind.Journal)) == first(partial,
      LightJournalAnchorBytes), "repair witness 70"
  assert readFile(directory & "/CURRENT") == current and readFile(lightChild(directory,
      ManagedFileKind.Snapshot)) == checkpoint, "repair witness 71"
  assert readFile(directory & "/KEEP") == "forensic sentinel", "repair witness 73"
  assert owner.append(fixture.next).error == FileError.None, "repair witness 74"
  assert owner.close == FileError.None, "repair witness 75"
  assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "repair witness 76"
  assert owner.preparedSnapshot.value.bytes == fixture.next.snapshot.bytes, "repair witness 77"
  assert owner.close == FileError.None, "repair witness 78"
  assert retained.prefix.snapshot.bytes == fixture.initial.bytes, "repair witness 79"
  retireLightJournal(directory)
proc changed(fixture: LightJournalFixture) {.raises.} =
  ## Every changed authority refuses before physical truncation, including equal-byte replacement of the selected inode.
  for mode in 0..<7:
    # Negative mutations deliberately bypass the cooperative lock solely to verify explicit stale-plan refusal.
    let directory = path("changed-" & $mode)
    seedLightJournal(directory, fixture, true)
    var recovery = default(LightJournalRecovery)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      resetHash(0)
      if recovery.opened: discard recovery.close
      if owner.opened: discard owner.close
    assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.None, "repair witness 94"
    let journalPath = lightChild(directory, ManagedFileKind.Journal)
    let original = readFile(journalPath)
    case mode
    of 0:
      var bytes = original
      bytes[bytes.len-1] = char(ord(bytes[bytes.len-1]) xor 1)
      writeFile(journalPath, bytes)
    of 1: writeFile(journalPath, original & "x")
    of 2: writeFile(journalPath, first(original, original.len-1))
    of 3:
      writeFile(directory & "/REPLACEMENT", original)
      var replacement = directory & "/REPLACEMENT"
      var selected = journalPath
      assert renameFile(replacement.toCString(), selected.toCString()) == 0, "repair witness 108"
    of 4:
      let selected = prepareLightJournalManifest(fixture.initial, ManagedEpoch(2),
          LightDeltaSequence(0), ByteLimit(LightJournalManifestBytes)).value
      writeFile(directory & "/CURRENT", lightText(selected.bytes))
    of 5: writeFile(lightChild(directory, ManagedFileKind.Snapshot), lightText(
        fixture.next.snapshot.encodedBytes))
    else: resetHash(1)
    let forensic = readFile(journalPath)
    resetIo()
    let refused = recovery.repair(owner)
    assert refused.error == (if mode == 6: FileError.BackendFailure else: FileError.RecoveryMismatch), "repair witness 117"
    assert not owner.opened and recovery.opened and recovery.plan.error ==
        FileError.RecoveryRequired, "repair witness 118"
    assert ioCalls(truncateIo) == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "repair witness 120"
    assert readFile(journalPath) == forensic, "repair witness 121"
    resetHash(0)
    assert recovery.close == FileError.None, "repair witness 123"
    retireLightJournal(directory)
proc failures(fixture: LightJournalFixture) {.raises.} =
  ## Actual pre-sync/truncate/post-sync refusals preserve explicit uncertainty and require a fresh owner.
  for mode in 0..<5:
    # A failed post-truncate barrier has a complete prefix on disk, whereas earlier refusals retain the original partial tail.
    let directory = path("failure-" & $mode)
    seedLightJournal(directory, fixture, true)
    var recovery = default(LightJournalRecovery)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      if recovery.opened: discard recovery.close
      if owner.opened: discard owner.close
    assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.None, "repair witness 137"
    resetIo()
    case mode
    of 1: armIo(truncateIo, 0, 1, failedIo)
    of 3: armIo(readIo, 4, 1, failedIo)
    of 4: armIo(closeIo, 2, 1, failedIo)
    else: armIo(syncIo, (if mode == 0: 0.cint else: 1.cint), 1, failedIo)
    let refused = recovery.repair(owner)
    assert refused.error == (if mode == 2: FileError.PublishedUnsynced else: FileError.IoFailure), "repair witness 142"
    assert pendingIo() == 0 and not owner.opened and recovery.plan.error ==
        FileError.RecoveryRequired, "repair witness 143"
    resetIo()
    assert recovery.close == FileError.None, "repair witness 146"
    let opened = openLightJournalCache(owner, directory, fixture.config)
    if mode == 2:
      # Strict reopen can confirm the truncated prefix after uncertainty without inventing a previous receipt.
      assert opened == FileError.None, "repair witness 150"
    else:
      # No implicit recovery occurs; a fresh explicit inspection must authorize the retry under its new held lease.
      assert opened == FileError.InvalidJournal, "repair witness 153"
      assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.None, "repair witness 154"
      assert recovery.repair(owner).error == FileError.None, "repair witness 155"
    assert owner.preparedSnapshot.value.bytes == fixture.initial.bytes, "repair witness 156"
    assert owner.append(fixture.next).error == FileError.None, "repair witness 157"
    assert owner.close == FileError.None, "repair witness 158"
    retireLightJournal(directory)
proc completeRefusals(fixture: LightJournalFixture) {.raises.} =
  ## Complete valid journals need no repair; complete corruption can never grant a salvage owner.
  let directory = path("complete-refusals")
  seedLightJournal(directory, fixture)
  var recovery = default(LightJournalRecovery)
  var owner = default(LightJournalCache)
  defer:
    if recovery.opened: discard recovery.close
    if owner.opened: discard owner.close
  assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.InvalidJournal, "anchor-only is complete"
  assert not recovery.opened, "complete refusal retires the inspection lease"
  assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "no leaked complete inspection lock"
  assert owner.append(fixture.next).error == FileError.None, "complete authenticated frame"
  assert owner.close == FileError.None, "close before deliberate fixture corruption"
  assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.InvalidJournal, "complete frame stream needs no repair"
  let journalPath = lightChild(directory, ManagedFileKind.Journal)
  var corrupt = readFile(journalPath)
  corrupt[corrupt.len-1] = char(ord(corrupt[corrupt.len-1]) xor 1)
  writeFile(journalPath, corrupt)
  resetIo()
  assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.InvalidBatch, "complete corruption is not an incomplete tail"
  assert not recovery.opened and ioCalls(truncateIo) == 0, "corrupt suffix grants no destructive authority"
  assert readFile(journalPath) == corrupt, "corrupt complete bytes stay forensic"
  retireLightJournal(directory)
proc crashed(fixture: LightJournalFixture, operation, skip: cint) {.raises.} =
  ## Exact stopped-child receipts qualify real truncate/sync boundaries while the parent observes the still-held lease.
  let directory = path("crash-" & $operation & "-" & $skip)
  seedLightJournal(directory, fixture, true)
  let original = readFile(lightChild(directory, ManagedFileKind.Journal))
  let current = readFile(directory & "/CURRENT")
  var recovery = default(LightJournalRecovery)
  var owner = default(LightJournalCache)
  defer:
    abortCrash()
    resetIo()
    if recovery.opened: discard recovery.close
    if owner.opened: discard owner.close
  let child = forkCrash(operation, skip)
  assert child >= 0, "repair witness 174"
  if child == 0:
    # Existing-byte inspection and locking are outside the observed destructive repair boundary.
    if inspectLightJournalTail(recovery, directory, fixture.config) != FileError.None: exitCrash(81)
    if startCrash() != 0: exitCrash(82)
    if recovery.repair(owner).error != FileError.None: exitCrash(83)
    exitCrash(0)
  if skip != 4096:
    # A stopped recovery owner retains both its selected append inode and the exclusive directory lease.
    assert waitCrash() == crashStopped, "repair witness 183"
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.Busy, "repair witness 184"
  let receipt = finishCrash()
  if skip == 4096: assert receipt == crashCompleted and crashCount() > 0 and crashCount() < 4096
  else: assert receipt == crashKilled and crashCount() == uint64(skip)+1
  resetIo()
  let expected = if operation == syncIo and skip == 0: original else: first(original, LightJournalAnchorBytes)
  assert readFile(lightChild(directory, ManagedFileKind.Journal)) == expected, "repair witness 190"
  assert readFile(directory & "/CURRENT") == current, "repair witness 191"
  let opened = openLightJournalCache(owner, directory, fixture.config)
  if expected.len == original.len:
    # A crash before truncate preserves the exact forensic tail and requires another explicit repair plan.
    assert opened == FileError.InvalidJournal, "repair witness 195"
    assert inspectLightJournalTail(recovery, directory, fixture.config) == FileError.None, "repair witness 196"
    assert recovery.repair(owner).error == FileError.None, "repair witness 197"
  else: assert opened == FileError.None
  assert owner.preparedSnapshot.value.bytes == fixture.initial.bytes, "repair witness 199"
  assert owner.close == FileError.None, "repair witness 200"
  retireLightJournal(directory)
proc main() {.raises.} =
  ## Positive, stale, native-failure, process-death and ownership cases share an independently rooted fixture.
  let fixture = lightFixture()
  normal(fixture)
  changed(fixture)
  failures(fixture)
  completeRefusals(fixture)
  for operation in [syncIo, truncateIo]:
    # Completed controls establish that each observed operation reaches a real successful repair boundary.
    crashed(fixture, operation, 4096)
  crashed(fixture, syncIo, 0)
  crashed(fixture, truncateIo, 0)
  crashed(fixture, syncIo, 1)
  let directory = path("arc")
  seedLightJournal(directory, fixture, true)
  for index in 0..<10: inspected(directory, fixture) # Warm the identical explicit inspection/retirement path.
  let before = getOccupiedMem()
  for index in 0..<1000: inspected(directory, fixture)
  let after = getOccupiedMem()
  assert before == after, "repair witness 220"
  recordArcRelease("storage_light_journal_repair", 1000, before, after)
  retireLightJournal(directory)
try:
  main()
except:
  quit(2)
echo "PASS light journal repair: held-inode exact-plan revalidation, explicit prefix truncation and crash-safe lease transfer"
