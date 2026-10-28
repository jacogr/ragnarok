# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real durable quota eviction matches manual frames, binds policy/position and survives witnessed append deaths through explicit recovery.
# @@Verification={"arc":"storage_light_retained_journal_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../support/storage_crash
import ../../support/storage_light_root
import ../../support/storage_light_journal
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/light_journal_cache as storage_light_journal_cache
import ../../../src/storage/light_journal_replay as storage_light_journal_replay
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Preparation/publication observations distinguish verified proof work from durable IO.
proc refuseAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Every actual proof, image and frame checksum boundary receives a consumed provider refusal.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## A prepared append must never rehash its retained target.
func retention(): LightRetentionLimits =
  ## Three retained queries force one old-query removal when the fourth protected query arrives.
  LightRetentionLimits(items: ElementLimit(3), valueBytes: ByteLimit(128), bytes: ByteLimit(8192),
    entries: ElementLimit(4), evictions: ElementLimit(1))
proc seed(path: string, fixture: LightRootFixture): PreparedLightSnapshot =
  ## Start with three known queries and retain a detached independent absence proof for the fourth.
  result = fixture.source.forget([lightKey(255)]).value
  var owner = default(LightJournalCache)
  assert initializeLightJournalCache(owner, path, fixture.oldConfig, result).error ==
      FileError.None, "seed retained journal"
  assert owner.close == FileError.None, "retire initializer"
proc cycle(owner: LightJournalCache, fixture: LightRootFixture, count: int) =
  ## Copied success and last-checksum refusal retain no predecessor image or native lease chain.
  let prepared = prepareLightRetainedUpdate(owner, [fixture.sourceProofs[3]], retention()).value
  let copied = prepared
  assert copied.frameCount == 1 and copied.snapshot.cache.len == 3, "one retained frame"
  refuseAfter(cint(count-1))
  assert prepareLightRetainedUpdate(owner, [fixture.sourceProofs[3]], retention()).error ==
      FileError.BackendFailure, "late frame checksum refusal"
  resetHash(0)
proc normal(fixture: LightRootFixture) {.raises.} =
  ## Independent manual preparation proves exact canonical output, one barrier and original-reader semantics.
  let path = "retained-normal-" & $storageProcessId()
  let source = seed(path, fixture)
  let manual = prepareLightDelta(source, LightDeltaSequence(1), [fixture.sourceProofs[3]],
    [lightKey(0)], fixture.oldConfig.journal.frame).value
  let expected = prepareLightSnapshot(fixture.oldConfig.chain, fixture.oldConfig.root,
    [fixture.sourceProofs[1], fixture.sourceProofs[2], fixture.sourceProofs[3]],
        fixture.oldConfig.snapshot).value
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None, "open retained baseline"
  let held = owner.preparedSnapshot.value
  resetHash(0)
  resetIo()
  let prepared = prepareLightRetainedUpdate(owner, [fixture.sourceProofs[3]], retention()).value
  let hashes = int(calls())
  assert hashes == fixture.sourceProofs[3].proof.nodes.len+2, "incoming proof plus image/frame checksums"
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "preparation has no IO"
  assert prepared.byteLength == manual.byteLength and prepared.snapshot.encodedBytes ==
      expected.encodedBytes, "manual canonical target and frame extent"
  for index in 0..<10: cycle(owner, fixture, hashes)
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(owner, fixture, hashes)
  let after = getOccupiedMem()
  assert before == after, "retained frame candidates completely retire"
  recordArcRelease("storage_light_retained_journal", 1000, before, after)
  for skip in 0..<hashes:
    refuseAfter(cint(skip))
    assert prepareLightRetainedUpdate(owner, [fixture.sourceProofs[3]], retention()).error ==
        FileError.BackendFailure, "exact provider refusal"
    assert calls() == cint(skip+1) and owner.preparedSnapshot.value.encodedBytes ==
        source.encodedBytes, "provider failure preserves source"
  resetHash(0)
  resetIo()
  let log = readFile(lightChild(path, ManagedFileKind.Journal))
  assert owner.append(prepared).error == FileError.None, "durable retained append"
  assert calls() == 0 and ioCalls(writeIo) == 1 and ioCalls(syncIo) == 1 and ioCalls(renameIo) == 0, "one append barrier without rehash/rename"
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == log & lightText(
      manual.encodedBytes), "exact manually authored retained frame"
  assert owner.snapshot.value.lookup(lightKey(0)).error == LightCacheError.UnknownKey, "evicted positive becomes unknown"
  assert owner.snapshot.value.lookup(lightKey(255)).value.kind == StateLookupKind.Absent, "incoming authenticated absence"
  assert held.cache.lookup(lightKey(0)).value.bytes[0] == 7, "old reader survives eviction"
  assert owner.append(prepared).error == FileError.StaleView, "same prepared eviction cannot duplicate update"
  assert owner.admitRetained([], retention()).error == FileError.None and uint64(
      owner.sequence.value) == 2, "durable no-op preserves ordinary sequence semantics"
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  assert uint64(owner.sequence.value) == 2 and owner.preparedSnapshot.value.encodedBytes ==
      expected.encodedBytes, "strict retained reopen"
  assert owner.close == FileError.None
  retireLightJournal(path)
proc policies(fixture: LightRootFixture) {.raises.} =
  ## Every journal policy scalar, including safe loosening, refuses old batches before publication work.
  let path = "retained-policy-" & $storageProcessId()
  discard seed(path, fixture)
  var owner = default(LightJournalCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  let prepared = prepareLightRetainedUpdate(owner, [fixture.sourceProofs[3]], retention()).value
  let ordinary = prepareLightJournalBatch(owner, [LightJournalEdit(forgotten: @[lightKey(128)])]).value
  assert owner.close == FileError.None
  for mode in 0..<9:
    var changed = fixture.oldConfig
    let direction = if mode mod 2 == 0: 1'u64 else: 0'u64
    if mode < 2: changed.journal.frames = ElementLimit(63+2*direction)
    elif mode < 4: changed.journal.bytes = ByteLimit(65535+2*direction)
    elif mode < 6: changed.journal.frame.items = ElementLimit(3+2*direction)
    elif mode < 8: changed.journal.frame.bytes = ByteLimit(4095+2*direction)
    else: changed.snapshot.cache.writes = ElementLimit(3)
    assert openLightJournalCache(owner, path, changed) == FileError.None, "reopen with explicit valid changed policy"
    resetIo()
    resetHash(0)
    assert owner.append(prepared).error == FileError.InvalidBatch and owner.append(
        ordinary).error == FileError.InvalidBatch, "exact retained and ordinary batch policy binding"
    assert calls() == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0, "changed policy refuses without work"
    assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  let compact = prepareLightCompaction(owner, owner.epoch.value, owner.sequence.value).value
  assert owner.compact(compact).error == FileError.None
  resetIo()
  assert owner.append(prepared).error == FileError.StaleView and ioCalls(writeIo) == 0, "same-image physical compaction stales retained frame"
  let fresh = prepareLightRetainedUpdate(owner, [fixture.sourceProofs[3]], retention()).value
  let forward = prepareLightRootAdvance(owner, owner.epoch.value, owner.sequence.value,
      fixture.newConfig.root, fixture.destination).value
  assert owner.advanceRoot(forward).error == FileError.None
  assert owner.append(fresh).error == FileError.WrongIdentity, "new-root selection rejects old retained evidence"
  let back = prepareLightRootAdvance(owner, owner.epoch.value, owner.sequence.value,
      fixture.oldConfig.root, fixture.source.forget([lightKey(255)]).value).value
  assert owner.advanceRoot(back).error == FileError.None
  assert owner.append(fresh).error == FileError.StaleView, "same-root image and sequence return remains physically stale"
  for epoch in 1..3: assert owner.cleanupRetiredEpoch(ManagedEpoch(epoch)) == FileError.None
  assert owner.close == FileError.None
  retireRootEpoch(path, ManagedEpoch(4))
  retireLightJournal(path)
proc refusal(fixture: LightRootFixture) {.raises.} =
  ## Frame/global capacities precede crypto and leave confirmed knowledge, position and bytes intact.
  let path = "retained-refusal-" & $storageProcessId()
  let source = seed(path, fixture)
  let frame = prepareLightDelta(source, LightDeltaSequence(1), [fixture.sourceProofs[3]], [lightKey(
      0)], fixture.oldConfig.journal.frame).value
  var owner = default(LightJournalCache)
  defer:
    resetHash(0)
    resetIo()
    if owner.opened: discard owner.close
  assert prepareLightRetainedUpdate(owner, [], retention()).error == FileError.Uninitialized
  for mode in 0..3:
    var config = fixture.oldConfig
    if mode == 0: config.journal.frames = ElementLimit(0)
    elif mode == 1: config.journal.frame.items = ElementLimit(1)
    elif mode == 2: config.journal.frame.bytes = ByteLimit(frame.byteLength-1)
    else: config.journal.bytes = ByteLimit(98+frame.byteLength-1)
    assert openLightJournalCache(owner, path, config) == FileError.None
    resetHash(0)
    resetIo()
    assert owner.admitRetained([fixture.sourceProofs[3]], retention()).error ==
        FileError.LimitExceeded, "capacity refusal"
    assert calls() == 0 and ioCalls(writeIo) == 0 and owner.preparedSnapshot.value.encodedBytes ==
        source.encodedBytes, "capacity preserves confirmed source without crypto"
    assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  assert owner.admitRetained([fixture.destinationProofs[0]], retention()).error ==
      FileError.InvalidBatch, "foreign-root proof cannot evict"
  assert owner.preparedSnapshot.value.encodedBytes == source.encodedBytes
  assert owner.close == FileError.None
  retireLightJournal(path)
proc interrupted(fixture: LightRootFixture, operation, skip: cint, chunk: int,
    injected: bool): uint64 {.raises.} =
  ## Separate EIO injection and actual stopped-child deaths preserve exact frame prefixes for strict or explicit recovery.
  let path = "retained-stop-" & $storageProcessId() & "-" & $operation & "-" & $skip & "-" &
      $chunk & "-" & $injected
  let source = seed(path, fixture)
  let frame = prepareLightDelta(source, LightDeltaSequence(1), [fixture.sourceProofs[3]], [lightKey(
      0)], fixture.oldConfig.journal.frame).value
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  var recovery = default(LightJournalRecovery)
  defer:
    abortCrash()
    resetIo()
    if recovery.opened: discard recovery.close
    if contender.opened: discard contender.close
    if owner.opened: discard owner.close
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None
  let prepared = prepareLightRetainedUpdate(owner, [fixture.sourceProofs[3]], retention()).value
  let oldLog = readFile(lightChild(path, ManagedFileKind.Journal))
  let oldCurrent = readFile(path & "/CURRENT")
  let oldCheckpoint = readFile(lightChild(path, ManagedFileKind.Snapshot))
  if injected:
    # Refused writes may leave zero or bounded partial progress; refused barriers may leave a complete authenticated frame.
    resetIo()
    if chunk > 0: limitWrites(csize_t(chunk))
    armIo(operation, skip, 1, failedIo)
    let expected = if operation == syncIo: FileError.PublishedUnsynced else: FileError.IoFailure
    assert owner.append(prepared).error == expected and pendingIo() == 0, "consumed retained-append IO refusal"
    assert owner.snapshot.error == FileError.RecoveryRequired, "uncertain owner exposes no fresh eviction state"
    result = uint64(skip)
    resetIo()
    assert owner.close == FileError.None
  else:
    # The child reopens the same exact predecessor; only actual append IO is armed for process death.
    assert owner.close == FileError.None
    resetIo()
    let child = forkCrash(operation, skip)
    assert child >= 0
    if child == 0:
      if openLightJournalCache(owner, path, fixture.oldConfig) != FileError.None: exitCrash(81)
      if chunk > 0: limitWrites(csize_t(chunk))
      if startCrash() != 0: exitCrash(82)
      if owner.append(prepared).error != FileError.None: exitCrash(83)
      exitCrash(0)
    if skip != 4096:
      assert waitCrash() == crashStopped, "exact successful retained append stop"
      assert openLightJournalCache(contender, path, fixture.oldConfig) == FileError.Busy
    let receipt = finishCrash()
    result = crashCount()
    assert (skip == 4096 and receipt == crashCompleted and result > 0) or
      (skip != 4096 and receipt == crashKilled and result == uint64(skip)+1), "real completion or stop/kill/reap receipt"
    resetIo()
  let extent = if operation == writeIo:
    (if chunk > 0 and skip != 4096: min(frame.byteLength, int(result)*chunk)
      elif injected: 0 else: frame.byteLength)
    else: frame.byteLength
  let input = readFile(lightChild(path, ManagedFileKind.Journal))
  assert input.len == oldLog.len+extent, "exact witnessed retained-frame extent"
  for index in 0..<oldLog.len: assert input[index] == oldLog[index], "unchanged predecessor journal prefix"
  for index in 0..<extent: assert byte(input[oldLog.len+index]) == frame.encodedBytes[index], "authored retained-frame prefix"
  assert readFile(path & "/CURRENT") == oldCurrent and readFile(lightChild(path,
      ManagedFileKind.Snapshot)) == oldCheckpoint
  let opened = openLightJournalCache(owner, path, fixture.oldConfig)
  if extent > 0 and extent < frame.byteLength:
    # Incomplete evidence authorizes no partial eviction; explicit held-inode repair retains the original whole-frame prefix.
    assert opened == FileError.InvalidJournal and not owner.opened
    assert inspectLightJournalTail(recovery, path, fixture.oldConfig) == FileError.None
    assert uint64(recovery.plan.value.prefix.sequence) == 0 and
        recovery.plan.value.prefix.snapshot.encodedBytes == source.encodedBytes
    assert recovery.repair(owner).error == FileError.None
  else:
    assert opened == FileError.None, "strict complete-prefix reopen"
  resetIo()
  if extent < frame.byteLength:
    assert owner.preparedSnapshot.value.encodedBytes == source.encodedBytes, "no eviction prefix before a complete frame"
    assert owner.append(prepared).error == FileError.None, "retry exact original plan after explicit source recovery"
  else:
    assert owner.append(prepared).error == FileError.StaleView, "complete retained frame is never duplicated"
  assert owner.preparedSnapshot.value.encodedBytes == frame.snapshot.encodedBytes and uint64(
      owner.sequence.value) == 1
  assert owner.admitRetained([fixture.sourceProofs[0]], retention()).error == FileError.None, "following protected positive admission"
  assert uint64(owner.sequence.value) == 2 and owner.snapshot.value.lookup(lightKey(0)).value.bytes[0] == 7
  assert source.cache.lookup(lightKey(0)).value.bytes[0] == 7, "old reader survives fault and process recovery"
  assert owner.close == FileError.None
  assert openLightJournalCache(owner, path, fixture.oldConfig) == FileError.None and uint64(
      owner.sequence.value) == 2
  assert owner.close == FileError.None
  retireLightJournal(path)
proc main() {.raises.} =
  ## Native controls qualify one atomic frame, every successful short write and barrier, plus independent IO-refusal paths.
  let fixture = rootFixture()
  normal(fixture)
  policies(fixture)
  refusal(fixture)
  discard interrupted(fixture, writeIo, 0, 0, true)
  discard interrupted(fixture, writeIo, 1, 64, true)
  discard interrupted(fixture, syncIo, 0, 0, true)
  let source = fixture.source.forget([lightKey(255)]).value
  let manual = prepareLightDelta(source, LightDeltaSequence(1), [fixture.sourceProofs[3]],
    [lightKey(0)], fixture.oldConfig.journal.frame).value
  var controls = 0
  var killed = 0
  for chunk in [0, 64]:
    for operation in [writeIo, syncIo]:
      let count = interrupted(fixture, operation, 4096, chunk, false)
      assert count > 0 and count < 64
      let expected = if operation == syncIo or chunk == 0: 1 else: (
        manual.byteLength+chunk-1) div chunk
      assert count == uint64(expected), "independently counted real append boundaries"
      controls += 1
      for skip in 0..<int(count):
        discard interrupted(fixture, operation, cint(skip), chunk, false)
        killed += 1
  let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
  if evidence.len > 0:
    let counts = "{\"controls\":" & $controls & ",\"killed_boundaries\":" & $killed & "}\n"
    writeFile(evidence & "/storage_light_retained_journal_process_crashes.json", counts)
try:
  main()
except:
  quit(2)
echo "PASS retained light journal: exact policy/position, one atomic eviction frame and explicit process/fault recovery"
