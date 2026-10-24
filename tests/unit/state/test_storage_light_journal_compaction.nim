# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared light checkpoint compaction preserves global sequence and separates confirmed selection from old-handle retirement.
# @@Verification={"arc":"storage_light_journal_compaction_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io, storage_light_journal]
import ../../../src/storage/[light_journal_cache, light_journal_manifest, light_delta,
  light_snapshot, light_journal_replay, database_identity, managed_io, managed_manifest,
  file_errors, durability]
import ../../../src/codec/bounded
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Opaque compaction publication performs no provider work after private preparation.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Both manifest and anchor preparation hashes must refuse before IO without poisoning.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Stale/exhausted positions precede hashing, and preparation performs only fixed metadata hashes.
proc renameFile(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Test-only maximum-counter fixtures relocate only their exact owned epoch files before strict open.
proc path(suffix: string): string =
  ## Native suites own their isolated ignored working directory.
  "light-compaction-" & $storageProcessId() & "-" & suffix
proc retireEpoch(path: string, epoch: ManagedEpoch) =
  ## Retire only exact known fixture epoch children after all native owners close.
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    var file = lightChild(path, kind, epoch)
    let removed = posix.unlink(file.toCString())
    if removed != 0: assert posix.errno() == ENOENT, "only an absent exact fixture child is harmless"
proc cycle(owner: LightJournalCache, epoch: ManagedEpoch, sequence: LightDeltaSequence) =
  ## Candidate copies retain immutable proof images and tiny fixed metadata, never the native lease.
  let prepared = prepareLightCompaction(owner, epoch, sequence).value
  let copied = prepared
  assert copied.initialized and uint64(copied.epoch) == uint64(epoch)+1, "checked next physical epoch"
  assert uint64(copied.sequence) == uint64(sequence), "unchanged global sequence"
proc normal(fixture: LightJournalFixture) {.raises.} =
  ## Reset a full frame budget with a new atomic checkpoint while preserving exact evidence, readers and global sequence.
  let directory = path("normal")
  var settings = fixture.config
  settings.journal.frames = ElementLimit(1)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert not default(PreparedLightCompaction).initialized, "default candidate has no authority"
  assert owner.compact(default(PreparedLightCompaction)).error == FileError.Uninitialized, "default owner refuses"
  assert initializeLightJournalCache(owner, directory, settings, fixture.initial).error ==
      FileError.None, "initialize compaction baseline"
  let initial = owner.preparedSnapshot.value
  let stale = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(0)).value
  assert owner.append(fixture.next).error == FileError.None, "fill configured frame budget"
  assert owner.append(fixture.following).error == FileError.LimitExceeded, "full budget precedes IO"
  let held = owner.preparedSnapshot.value
  let current = readFile(directory & "/CURRENT")
  let checkpoint = readFile(lightChild(directory, ManagedFileKind.Snapshot))
  let journal = readFile(lightChild(directory, ManagedFileKind.Journal))
  resetIo()
  resetHash(1)
  assert owner.compact(stale).error == FileError.StaleView, "stale sequence cannot replace a checkpoint"
  assert prepareLightCompaction(owner, ManagedEpoch(2), LightDeltaSequence(1)).error ==
      FileError.StaleView, "stale epoch refuses"
  assert prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(0)).error ==
      FileError.StaleView, "stale sequence refuses"
  assert calls() == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "stale position precedes hashes and IO"
  for successful in 0..<2:
    # Every fixed metadata provider refusal leaves current selection and all fresh observations confirmed.
    refuseAfter(cint(successful))
    let refused = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(1))
    assert refused.error == FileError.BackendFailure, "typed private preparation refusal"
    assert calls() == cint(successful+1), "intended provider boundary consumed"
    assert owner.preparedSnapshot.value.bytes == held.bytes, "pure refusal preserves authority"
  resetHash(0)
  let prepared = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(1)).value
  assert uint64(prepared.epoch) == 2 and uint64(prepared.sequence) == 1 and calls() == 2, "only two fixed metadata hashes"
  resetIo()
  resetHash(1)
  let compacted = owner.compact(prepared)
  assert compacted.error == FileError.None, "prepared publication does not rehash proofs or metadata"
  assert calls() == 0, "zero provider calls during publication"
  resetHash(0)
  let receipt = compacted.value
  assert uint64(receipt.previousEpoch) == 1 and uint64(receipt.epoch) == 2, "confirmed physical selection"
  assert uint64(receipt.sequence) == 1 and receipt.retirement == FileError.None, "global sequence preserved with separate successful retirement"
  assert ioCalls(writeIo) == 3 and ioCalls(syncIo) == 8 and ioCalls(renameIo) == 1, "exact checkpoint anchor CURRENT publication"
  assert readFile(directory & "/CURRENT") != current, "new distinct manifest selected"
  assert readFile(lightChild(directory, ManagedFileKind.Snapshot)) == checkpoint, "old checkpoint retained"
  assert readFile(lightChild(directory, ManagedFileKind.Journal)) == journal, "old journal retained"
  assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))) == lightText(
      held.encodedBytes), "new checkpoint is exact current evidence"
  let selectedBytes = readFile(directory & "/CURRENT")
  var selected = newSeq[byte](selectedBytes.len)
  for index in 0..<selected.len: selected[index] = byte(selectedBytes[index])
  let manifest = decodeLightJournalManifest(selected, settings.chain, settings.root, ByteLimit(
      LightJournalManifestBytes)).value
  assert uint64(manifest.epoch) == 2 and uint64(manifest.baseSequence) == 1, "manifest separates epoch and baseline"
  assert readFile(lightChild(directory, ManagedFileKind.Journal, ManagedEpoch(2))) == lightText(
      encodeLightJournalAnchor(manifest, ByteLimit(LightJournalAnchorBytes)).value), "new journal has only its exact anchor"
  assert owner.journalBytes.value == uint64(LightJournalAnchorBytes) and uint64(
      owner.sequence.value) == 1, "compaction resets physical usage only"
  assert owner.preparedSnapshot.value.bytes == held.bytes, "compaction never changes proof knowledge"
  assert owner.compact(prepared).error == FileError.StaleView, "same completed plan cannot advance another epoch"
  assert owner.append(fixture.following).error == FileError.None, "fresh frame budget accepts the next global sequence"
  assert uint64(owner.sequence.value) == 2 and owner.preparedSnapshot.value.bytes ==
      fixture.following.snapshot.bytes, "following frame remains bound after checkpoint replacement"
  assert owner.close == FileError.None, "retire new append before directory"
  assert openLightJournalCache(owner, directory, settings) == FileError.None, "strict reopen new checkpoint and frame"
  assert uint64(owner.epoch.value) == 2 and uint64(owner.sequence.value) == 2, "reopen preserves distinct counters"
  for index in 0..<10: cycle(owner, ManagedEpoch(2), LightDeltaSequence(
      2)) # Warm exact immutable candidate lifecycle.
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(owner, ManagedEpoch(2), LightDeltaSequence(2))
  let after = getOccupiedMem()
  assert before == after, "prepared candidates retain no predecessor or lease chain"
  recordArcRelease("storage_light_journal_compaction", 1000, before, after)
  assert owner.close == FileError.None, "close while prepared plans remain alive"
  assert uint64(prepared.epoch) == 2 and held.bytes == fixture.next.snapshot.bytes and
      initial.bytes == fixture.initial.bytes, "retained plans and old readers remain immutable"
  assert openLightJournalCache(owner, directory, settings) == FileError.None, "retained plan does not hold LOCK"
  assert owner.close == FileError.None, "explicit final retirement"
  retireEpoch(directory, ManagedEpoch(2))
  retireLightJournal(directory)
proc failures(fixture: LightJournalFixture) {.raises.} =
  ## Preselection failures grant no receipt; confirmed selection with old-close failure still returns an explicit retirement diagnostic.
  for mode in 0..<10:
    # Actual write/sync/rename/read/close errors and existing forensic children cover every publication phase.
    let directory = path("failure-" & $mode)
    seedLightJournal(directory, fixture)
    var owner = default(LightJournalCache)
    defer:
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "open fault baseline"
    assert owner.append(fixture.next).error == FileError.None, "confirmed semantic head before physical replacement"
    let held = owner.preparedSnapshot.value
    let prepared = prepareLightCompaction(owner, ManagedEpoch(1), LightDeltaSequence(1)).value
    let selected = readFile(directory & "/CURRENT")
    let checkpoint = readFile(lightChild(directory, ManagedFileKind.Snapshot))
    let journal = readFile(lightChild(directory, ManagedFileKind.Journal))
    if mode == 6: writeFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)), "unknown candidate sentinel")
    if mode == 7: writeFile(directory & "/CURRENT.next", "unknown staging sentinel")
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
    else: discard # Existing exact candidate/staging names require no injected native failure.
    let outcome = owner.compact(prepared)
    assert pendingIo() == 0, "all intended compaction faults consumed"
    resetIo()
    if mode == 5:
      # CURRENT and its directory barrier completed; retirement failure cannot erase that confirmed result or authorize an implicit retry.
      assert outcome.error == FileError.None and outcome.value.retirement == FileError.IoFailure, "confirmed selection has separate retirement error"
      assert uint64(outcome.value.epoch) == 2 and uint64(outcome.value.sequence) == 1, "receipt identifies the selected head"
    else:
      let expected = if mode == 4: FileError.PublishedUnsynced elif (mode == 6 or mode ==
          7): FileError.AlreadyExists else: FileError.IoFailure
      assert outcome.error == expected, "preconfirmation failure has no completed receipt"
    assert readFile(lightChild(directory, ManagedFileKind.Snapshot)) == checkpoint, "old checkpoint never changes"
    assert readFile(lightChild(directory, ManagedFileKind.Journal)) == journal and held.bytes ==
        fixture.next.snapshot.bytes, "old journal and readers remain exact"
    if mode == 6:
      # Refusing an existing candidate name touches no selected bytes and does not poison the otherwise confirmed owner.
      assert owner.preparedSnapshot.value.bytes == held.bytes, "existing candidate leaves live authority confirmed"
      assert readFile(lightChild(directory, ManagedFileKind.Snapshot, ManagedEpoch(2))) ==
          "unknown candidate sentinel", "unknown candidate is never overwritten"
      assert owner.append(fixture.following).error == FileError.None, "ordinary append can continue after a pure name refusal"
    else:
      assert owner.preparedSnapshot.error == FileError.RecoveryRequired, "uncertainty poisons fresh authority"
      assert owner.compact(prepared).error == FileError.RecoveryRequired, "uncertain compaction is not implicitly retried"
    if (mode != 4 and mode != 5): assert readFile(directory & "/CURRENT") == selected, "preselection failures retain CURRENT"
    assert owner.close == FileError.None, "close both native lease resources after uncertainty"
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "strict reopen verifies actual selected epoch"
    assert uint64(owner.epoch.value) == (if (mode == 4 or mode == 5): 2'u64 else: 1'u64), "actual manifest decides epoch after uncertainty"
    assert uint64(owner.sequence.value) == (if mode == 6: 2'u64 else: 1'u64), "global sequence never advances through compaction"
    if (mode == 4 or mode == 5): assert owner.compact(prepared).error == FileError.StaleView, "confirmed replacement cannot be retried from its previous position"
    assert owner.close == FileError.None, "retire strict reopened owner"
    retireEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc seedCounters(directory: string, fixture: LightJournalFixture, epoch: ManagedEpoch,
    sequence: LightDeltaSequence) {.raises.} =
  ## Construct exact maximum-counter local format fixtures under no live lease before strict admission.
  seedLightJournal(directory, fixture)
  if uint64(epoch) != 1:
    # Only canonical exact owned filenames are relocated; the production reader still authenticates the final selected transport.
    for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
      var oldName = lightChild(directory, kind)
      var newName = lightChild(directory, kind, epoch)
      assert renameFile(oldName.toCString(), newName.toCString()) == 0, "relocate known maximum epoch fixture"
  let selected = prepareLightJournalManifest(fixture.initial, epoch, sequence, ByteLimit(
      LightJournalManifestBytes)).value
  writeFile(directory & "/CURRENT", lightText(selected.bytes))
  writeFile(lightChild(directory, ManagedFileKind.Journal, epoch), lightText(
      encodeLightJournalAnchor(selected, ByteLimit(LightJournalAnchorBytes)).value))
proc maxima(fixture: LightJournalFixture) {.raises.} =
  ## Physical epoch exhaustion refuses before arithmetic/IO, while maximum global sequence can still be checkpointed unchanged.
  for mode in 0..<2:
    let directory = path("maximum-" & $mode)
    let epoch = if mode == 0: ManagedEpoch(high(uint64)) else: ManagedEpoch(1)
    let sequence = if mode == 1: LightDeltaSequence(high(uint64)) else: LightDeltaSequence(0)
    seedCounters(directory, fixture, epoch, sequence)
    var owner = default(LightJournalCache)
    defer:
      resetHash(0)
      resetIo()
      if owner.opened: discard owner.close
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "strict maximum metadata admission"
    resetIo()
    if mode == 0:
      resetHash(1)
      assert prepareLightCompaction(owner, epoch, sequence).error == FileError.EpochExhausted, "epoch cannot wrap"
      assert calls() == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "epoch exhaustion precedes work"
      resetHash(0)
    else:
      let prepared = prepareLightCompaction(owner, epoch, sequence).value
      assert owner.compact(prepared).error == FileError.None, "compaction requires no sequence increment"
      assert uint64(owner.sequence.value) == high(uint64) and uint64(owner.epoch.value) == 2, "maximum sequence preserved"
      assert owner.update([], []).error == FileError.LimitExceeded, "updates still cannot wrap exhausted sequence"
    assert owner.close == FileError.None, "retire maximum fixture"
    assert openLightJournalCache(owner, directory, fixture.config) == FileError.None, "strict reopen maximum baseline"
    assert uint64(owner.sequence.value) == uint64(sequence), "durable unchanged sequence"
    assert owner.close == FileError.None, "final maximum fixture close"
    if mode == 0: retireEpoch(directory, epoch)
    else: retireEpoch(directory, ManagedEpoch(2))
    retireLightJournal(directory)
proc main() {.raises.} =
  ## One independently rooted fixture covers physical replacement, all refusal phases and distinct counter boundaries.
  let fixture = lightFixture()
  normal(fixture)
  failures(fixture)
  maxima(fixture)
try:
  main()
except:
  quit(2)
echo "PASS light journal compaction: atomic checkpoint epochs, unchanged global sequence and explicit confirmed retirement outcomes"
