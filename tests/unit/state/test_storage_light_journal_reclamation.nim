# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit journal reclamation validates selected authority, preserves unknown candidates and synchronizes idempotent absence.
# @@Verification={"arc":"storage_light_journal_reclamation_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io, storage_light_journal]
import ../../../src/storage/[light_journal_cache, light_journal_manifest, light_journal_replay,
  light_delta, light_snapshot, database_identity, managed_io, managed_manifest, file_errors]
import ../../../src/codec/bounded
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Selected-head provider refusal must poison fresh authority before any namespace deletion.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Invalid retention positions refuse before hashing or IO.
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Test-only exact child presence observations never establish production selection.
proc renameFile(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Equal-byte selected inode replacement deliberately bypasses the cooperative lease for a negative witness.
proc linkFile(source, target: cstring): cint {.importc: "symlink", cdecl, header: "<unistd.h>".}
  ## Unselected symlinks must never satisfy regular-prefix preflight or be followed.
proc exists(path: string): bool =
  ## Observe only exact owned fixture children.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc path(suffix: string): string =
  ## Native test fixtures live directly in Hastur's isolated ignored working directory.
  "light-reclamation-" & $storageProcessId() & "-" & suffix
proc retireEpoch(path: string, epoch: ManagedEpoch) =
  ## Explicit test retirement names only known owned epoch files after every native owner closes.
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    var file = lightChild(path, kind, epoch)
    let removed = posix.unlink(file.toCString())
    if removed != 0: assert posix.errno() == ENOENT, "only missing known fixture names are harmless"
proc compacted(path: string, fixture: LightJournalFixture,
    following = false): PreparedLightCompaction =
  ## Build a genuine selected epoch two, retaining its old exact plan for selected-target refusal tests.
  seedLightJournal(path, fixture)
  var owner = default(LightJournalCache)
  defer:
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "open compaction fixture"
  assert owner.append(fixture.next).error == FileError.None, "confirm first global frame"
  result = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(1)).value
  assert owner.compact(result).error == FileError.None, "select epoch two"
  if following: assert owner.append(fixture.following).error == FileError.None, "selected journal has a genuine following frame"
  assert owner.close == FileError.None, "release fixture lease"
proc cycle(owner: var LightJournalCache, expected: PreparedLightSnapshot) =
  ## Retire every bounded disk/replay scratch and compare the same confirmed immutable image before ARC sampling.
  assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "idempotent known-old cleanup"
  assert owner.preparedSnapshot.value.bytes == expected.bytes, "cleanup never changes proof knowledge"
proc normal(fixture: LightJournalFixture) {.raises.} =
  ## Past canonical epochs can be removed while selected and arbitrary future/unknown names remain byte-identical.
  let directory = path("normal")
  let oldPlan = compacted(directory, fixture, true)
  writeFile(directory & "/KEEP", "unknown sibling")
  writeFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(3)), "future sentinel")
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.Uninitialized, "closed owner grants no cleanup"
  assert owner.discardPending == FileError.Uninitialized, "closed owner cannot delete staging"
  assert owner.discardUnselectedCompaction(oldPlan) == FileError.Uninitialized, "closed owner cannot delete candidates"
  assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "open selected head"
  let held = owner.preparedSnapshot.value
  let current = readFile(directory & "/CURRENT")
  let checkpoint = readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)))
  let journal = readFile(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2)))
  resetIo()
  resetHash(1)
  for invalid in [ManagedEpoch(0), ManagedEpoch(2), ManagedEpoch(3)]:
    # Caller-selected zero/current/future positions never trigger hashing, reads or deletion.
    assert owner.cleanupRetiredEpoch(invalid) == FileError.InvalidRetention, "bounded retired epoch"
  assert owner.discardUnselectedCompaction(oldPlan) == FileError.InvalidRetention, "prepared target is already selected"
  assert owner.discardUnselectedCompaction(default(PreparedLightCompaction)) ==
      FileError.Uninitialized, "default plan grants no cleanup"
  assert calls() == 0 and ioCalls(readIo) == 0 and ioCalls(unlinkIo) == 0, "invalid positions precede work"
  resetHash(0)
  assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "explicit past pair cleanup"
  assert ioCalls(unlinkIo) == 2 and ioCalls(syncIo) == 3, "two removals and a final absence barrier"
  assert not exists(lightChild(directory, ManagedFileKind.Snapshot)) and not exists(lightChild(
      directory, ManagedFileKind.Journal)), "only old pair removed"
  resetIo()
  assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "already absent pair retry"
  assert ioCalls(unlinkIo) == 0 and ioCalls(syncIo) == 1, "already absent names still require a directory barrier"
  writeFile(directory & "/CURRENT.next", "unknown explicit staging payload")
  let candidate = prepareLightCompaction(owner, ManagedEpoch(2), LightDeltaSequence(2)).value
  assert owner.discardUnselectedCompaction(candidate) == FileError.RecoveryMismatch, "unknown future candidate bytes are not a prepared prefix"
  assert readFile(directory & "/CURRENT.next") == "unknown explicit staging payload", "candidate preflight preserves every staged file on refusal"
  assert owner.preparedSnapshot.error == FileError.None, "unselected prefix refusal does not erase confirmed selected authority"
  assert owner.discardPending == FileError.None, "separate explicit fixed-name staging cleanup"
  assert not exists(directory & "/CURRENT.next"), "only explicitly requested staging removed"
  assert readFile(directory & "/CURRENT") == current, "CURRENT remains exact"
  assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))) == checkpoint, "selected checkpoint remains exact"
  assert readFile(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2))) == journal, "selected journal remains exact"
  assert readFile(directory & "/KEEP") == "unknown sibling", "unknown sibling remains"
  assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(3))) ==
      "future sentinel", "future canonical slot remains"
  for index in 0..<10: cycle(owner, held) # Warm exact selected-head replay and already absent cleanup.
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(owner, held)
  let after = getOccupiedMem()
  assert before == after, "selected-head validation retains no scratch or reader chain"
  recordArcRelease("storage_light_journal_reclamation", 1000, before, after)
  assert owner.close == FileError.None, "retire selected lease"
  assert held.bytes == fixture.following.snapshot.bytes, "old reader survives physical reclamation and close"
  retireEpoch(directory, ManagedEpoch(2))
  retireEpoch(directory, ManagedEpoch(3))
  retireLightJournal(directory)
proc failures(fixture: LightJournalFixture) =
  ## Cleanup-only namespace uncertainty leaves the already confirmed selected head readable and permits explicit idempotent retries.
  for mode in 0..<5:
    let directory = path("failure-" & $mode)
    discard compacted(directory, fixture)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "open cleanup fault fixture"
    resetIo()
    if mode < 2: armIo(unlinkIo, cint(mode), 1, failedIo)
    else: armIo(syncIo, cint(mode-2), 1, failedIo)
    assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.IoFailure, "typed deletion/barrier refusal"
    assert pendingIo() == 0, "intended cleanup fault consumed"
    assert owner.preparedSnapshot.value.bytes == fixture.next.snapshot.bytes, "cleanup failure cannot roll back confirmed selection"
    let absent = not exists(lightChild(directory, ManagedFileKind.Snapshot)) and not exists(
        lightChild(directory, ManagedFileKind.Journal))
    resetIo()
    assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "explicit cleanup retry"
    assert not exists(lightChild(directory, ManagedFileKind.Snapshot)) and not exists(lightChild(
        directory, ManagedFileKind.Journal)), "both retired names absent"
    if absent: assert ioCalls(unlinkIo) == 0 and ioCalls(syncIo) == 1, "last-unlink barrier failure retries with a fresh final sync"
    assert owner.close == FileError.None, "retire fault fixture owner"
    retireEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc changed(fixture: LightJournalFixture) {.raises.} =
  ## Changed selected authority poisons the owner before deleting even one retired byte or name.
  for mode in 0..<4:
    let directory = path("changed-" & $mode)
    discard compacted(directory, fixture, true)
    var owner = default(LightJournalCache)
    defer:
      resetHash(0)
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "open mutation fixture"
    let held = owner.preparedSnapshot.value
    let oldCheckpoint = readFile(lightChild(directory, ManagedFileKind.Snapshot))
    let oldJournal = readFile(lightChild(directory, ManagedFileKind.Journal))
    case mode
    of 0:
      let selected = prepareLightJournalManifest(held, ManagedEpoch(3), LightDeltaSequence(2),
          ByteLimit(LightJournalManifestBytes)).value
      writeFile(directory & "/CURRENT", lightText(selected.bytes))
    of 1: writeFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)), lightText(
        fixture.initial.encodedBytes))
    of 2:
      var journal = lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2))
      var replacement = directory & "/REPLACEMENT"
      writeFile(replacement, readFile(journal))
      assert renameFile(replacement.toCString(), journal.toCString()) == 0, "equal bytes in another selected inode"
    else: resetHash(1)
    resetIo()
    let refused = owner.cleanupRetiredEpoch(ManagedEpoch(1))
    assert refused == (if mode == 3: FileError.BackendFailure else: FileError.RecoveryMismatch), "changed selected head refuses deletion"
    assert ioCalls(unlinkIo) == 0 and ioCalls(syncIo) == 0, "no destructive operation precedes exact selected authority"
    assert owner.preparedSnapshot.error == FileError.RecoveryRequired, "selected uncertainty poisons fresh observations"
    assert held.bytes == fixture.following.snapshot.bytes, "retained immutable reader remains valid"
    assert readFile(lightChild(directory, ManagedFileKind.Snapshot)) == oldCheckpoint and readFile(
        lightChild(directory, ManagedFileKind.Journal)) == oldJournal, "all retired forensic bytes remain"
    resetHash(0)
    assert owner.close == FileError.None, "retire poisoned selected owner"
    retireEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc candidates(fixture: LightJournalFixture) {.raises.} =
  ## Opaque plans authorize only their matching immediate unselected prefixes, including interrupted checkpoint/staging writes.
  for mode in 0..<6:
    let directory = path("candidate-" & $mode)
    seedLightJournal(directory, fixture)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "open candidate fixture"
    assert owner.append(fixture.next).error == FileError.None, "confirm candidate source image"
    let prepared = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(1)).value
    resetIo()
    if mode == 0:
      # The candidate checkpoint contains a genuine 64-byte prefix, with no journal or staged selection yet.
      limitWrites(64)
      armIo(writeIo, 1, 1, failedIo)
    elif mode == 1:
      # All checkpoint/anchor short chunks complete before the staged manifest's second short write refuses.
      let priorChunks = (fixture.next.snapshot.byteLength+63) div 64 + (
          LightJournalAnchorBytes+63) div 64
      assert priorChunks < 64, "bounded expected staging short-write position"
      limitWrites(64)
      armIo(writeIo, cint(priorChunks+1), 1, failedIo)
    else: armIo(renameIo, 0, 1, failedIo)
    assert owner.compact(prepared).error == FileError.IoFailure, "actual interrupted candidate publication"
    assert pendingIo() == 0, "intended candidate publication fault consumed"
    resetIo()
    assert owner.close == FileError.None, "close uncertain candidate publication owner"
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "strict reopen selects the unchanged old epoch"
    if mode == 3: writeFile(directory & "/CURRENT.next", "unknown staging sentinel")
    if mode == 4: writeFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)), "unknown candidate sentinel")
    if mode == 5: assert owner.append(fixture.following).error == FileError.None, "ordinary append may advance within the same physical epoch"
    writeFile(directory & "/KEEP", "unknown sibling")
    writeFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(3)), "future sentinel")
    if mode == 3 or mode == 4:
      # One unknown prefix refuses before any other canonical candidate or staging file is deleted.
      let snapshot = readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)))
      let journal = readFile(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2)))
      let staged = readFile(directory & "/CURRENT.next")
      resetIo()
      assert owner.discardUnselectedCompaction(prepared) == FileError.RecoveryMismatch, "unknown candidate content refuses"
      assert ioCalls(unlinkIo) == 0, "all candidates preflight before any unlink"
      assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))) ==
          snapshot and readFile(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2))) ==
          journal and readFile(directory & "/CURRENT.next") == staged, "preflight refusal preserves every candidate"
      assert owner.preparedSnapshot.error == FileError.None, "unknown unselected content does not erase selected authority"
      if mode == 3: assert owner.discardPending == FileError.None, "explicit fixed-name staging cleanup is separate"
      else: writeFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)), lightText(
          fixture.next.snapshot.encodedBytes)) # Restore the deliberately corrupted owned fixture for the positive prefix path.
    assert owner.discardUnselectedCompaction(prepared) == FileError.None, "explicit matching prepared candidate cleanup"
    assert not exists(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))) and
        not exists(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2))) and not exists(
        directory & "/CURRENT.next"), "only matching immediate candidate and staging removed"
    assert readFile(directory & "/KEEP") == "unknown sibling" and readFile(lightChild(directory,
        ManagedFileKind.Snapshot, ManagedEpoch(3))) == "future sentinel", "unknown and future names survive"
    let sequence = if mode == 5: LightDeltaSequence(2) else: LightDeltaSequence(1)
    assert uint64(owner.sequence.value) == uint64(sequence) and uint64(owner.epoch.value) == 1, "candidate cleanup changes no selected position"
    let retry = prepareLightCompaction(owner, ManagedEpoch(1), sequence).value
    assert owner.compact(retry).error == FileError.None, "cleaned namespace permits explicit fresh compaction"
    assert owner.discardUnselectedCompaction(retry) == FileError.InvalidRetention, "newly selected candidate can never be discarded"
    assert owner.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None, "retire old pair after confirmed replacement"
    assert owner.close == FileError.None, "retire candidate fixture lease"
    retireEpoch(directory, ManagedEpoch(2))
    retireEpoch(directory, ManagedEpoch(3))
    retireLightJournal(directory)
proc prefixChecks(fixture: LightJournalFixture) {.raises.} =
  ## Narrow managed prefix probes admit only bounded regular exact prefixes and never follow symlinks or accept CURRENT as a candidate.
  let directory = path("prefix")
  seedLightJournal(directory, fixture)
  var lease = default(ManagedDirectory)
  assert validateManagedFilePrefix(lease, ManagedFileKind.Snapshot, ManagedEpoch(1),
      fixture.initial.encodedBytes, fixture.config.snapshot.bytes) == FileError.Uninitialized, "unopened prefix probe refuses"
  assert openManagedDirectory(lease, directory) == FileError.None, "hold explicit prefix fixture lease"
  assert validateManagedFilePrefix(lease, ManagedFileKind.Current, ManagedEpoch(1),
      fixture.initial.encodedBytes, fixture.config.snapshot.bytes) == FileError.InvalidPath, "CURRENT is never an epoch candidate"
  resetIo()
  assert validateManagedFilePrefix(lease, ManagedFileKind.Snapshot, ManagedEpoch(1),
      fixture.initial.encodedBytes, ByteLimit(0)) == FileError.LimitExceeded, "expected bytes preflight before IO"
  assert ioCalls(readIo) == 0, "expected limit precedes file read"
  assert validateManagedFilePrefix(lease, ManagedFileKind.Snapshot, ManagedEpoch(1),
      fixture.initial.encodedBytes, fixture.config.snapshot.bytes) == FileError.None, "complete exact canonical prefix"
  assert validateManagedFilePrefix(lease, ManagedFileKind.Snapshot, ManagedEpoch(2),
      fixture.initial.encodedBytes, fixture.config.snapshot.bytes) == FileError.None, "only ENOENT is an absent optional candidate"
  var target = lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))
  var source = "CURRENT"
  assert linkFile(source.toCString(), target.toCString()) == 0, "owned negative symlink fixture"
  assert validateManagedFilePrefix(lease, ManagedFileKind.Snapshot, ManagedEpoch(2),
      fixture.initial.encodedBytes, fixture.config.snapshot.bytes) == FileError.IoFailure, "candidate symlink never followed"
  assert lease.close == FileError.None, "retire prefix lease"
  assert posix.unlink(target.toCString()) == 0, "retire only owned negative symlink"
  retireLightJournal(directory)
proc main() {.raises.} =
  ## Independent complete-root fixtures qualify selected, unselected, failure, stale and bounded-file authority as one review unit.
  let fixture = lightFixture()
  prefixChecks(fixture)
  normal(fixture)
  failures(fixture)
  changed(fixture)
  candidates(fixture)
try:
  main()
except:
  quit(2)
echo "PASS light journal reclamation: exact selected-head gates, prepared prefix cleanup and synchronized idempotent absence"
