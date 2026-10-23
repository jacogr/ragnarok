# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Grouped real-process journal bootstrap and append witnesses preserve exact namespace bytes, leases and explicit recovery.
import std/[assertions, syncio]
import ./[storage_io, storage_crash, storage_light_journal]
import ../../src/storage/[light_journal_cache, light_journal_manifest, light_journal_replay,
  light_delta, light_snapshot, light_state_cache, managed_io, managed_manifest, file_errors]
import ../../src/codec/bounded
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Test-only exact presence observations never supply production file-selection authority.
proc exists(path: string): bool =
  ## Observe only a known owned fixture child, with no directory scan or fallback selection.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc first(input: string, size: int): string =
  ## Independent exact prefix copying proves every observed completed write extent.
  assert size >= 0 and size <= input.len, "bounded crash fixture prefix"
  result = newString(size)
  for index in 0..<size: result[index] = input[index]
proc checkPrefix(input, expected: string) =
  ## A surviving unselected file must contain only authored bytes, never zero padding or another generation.
  assert input.len <= expected.len, "unselected file cannot exceed its authored extent"
  for index in 0..<input.len: assert input[index] == expected[index], "exact authored prefix"
proc supervise(path: string, fixture: LightJournalFixture, skip: cint,
    contender: var LightJournalCache): uint64 =
  ## Parent contention happens while the exact stopped child still owns its native lease; kill/reap requires its matching receipt.
  if skip != 4096:
    # Every selected boundary occurs after LOCK is acquired, including the first bootstrap lock sync.
    assert waitCrash() == crashStopped, "matching successful operation stop"
    assert openLightJournalCache(contender, path, fixture.config) == FileError.Busy, "stopped child retains LOCK"
    assert not contender.opened, "contention grants no parent authority"
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 4096, "positive completed control"
  else:
    assert receipt == crashKilled and result == uint64(skip)+1, "exact stop kill reap receipt"
  resetIo()
proc lightAppendCrash*(fixture: LightJournalFixture, following: bool,
    operation, skip: cint, shortWrites = false): uint64 {.raises.} =
  ## A sparse append changes only authored journal bytes; partial suffixes require explicit held-inode repair before retry.
  let path = "light-append-crash-" & $storageProcessId() & "-" & $following & "-" &
      $operation & "-" & $skip & "-" & $shortWrites
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
  assert openLightJournalCache(owner, path, fixture.config) == FileError.None, "open append baseline"
  if following:
    # The second-frame workload proves repair retains a genuinely authenticated nonempty frame prefix.
    assert owner.append(fixture.next).error == FileError.None, "confirm predecessor frame"
  let retained = owner.preparedSnapshot.value
  let oldSequence = uint64(owner.sequence.value)
  assert owner.close == FileError.None, "release parent lease before fork"
  let delta = if following: fixture.following else: fixture.next
  let original = readFile(lightChild(path, ManagedFileKind.Journal))
  let current = readFile(path & "/CURRENT")
  let checkpoint = readFile(lightChild(path, ManagedFileKind.Snapshot))
  let frame = lightText(delta.encodedBytes)
  writeFile(path & "/KEEP", "unselected forensic sentinel")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0, "adopt one test-owned child"
  if child == 0:
    # Strict verification and preparation are excluded from the observed append boundary.
    if openLightJournalCache(owner, path, fixture.config) != FileError.None: exitCrash(81)
    if shortWrites: limitWrites(64)
    if startCrash() != 0: exitCrash(82)
    if owner.append(delta).error != FileError.None: exitCrash(83)
    exitCrash(0)
  result = supervise(path, fixture, skip, contender)
  let extent = if shortWrites and operation == writeIo and skip != 4096:
    min(frame.len, int(result)*64) else: frame.len
  let selected = readFile(lightChild(path, ManagedFileKind.Journal))
  assert selected == original & first(frame, extent), "exact completed append prefix"
  assert readFile(path & "/CURRENT") == current, "append never rewrites CURRENT"
  assert readFile(lightChild(path, ManagedFileKind.Snapshot)) == checkpoint, "append never rewrites checkpoint"
  assert not exists(path & "/CURRENT.next"), "append creates no staged manifest"
  let opened = openLightJournalCache(owner, path, fixture.config)
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0, "strict open preserves namespace and tail"
  assert readFile(lightChild(path, ManagedFileKind.Journal)) == selected, "strict reopen preserves exact forensic bytes"
  if extent < frame.len:
    # Only a fresh explicit inspection can discard the incomplete entire next frame under its actual held lease.
    assert opened == FileError.InvalidJournal and not owner.opened, "partial append never grants strict success"
    assert inspectLightJournalTail(recovery, path, fixture.config) == FileError.None, "inspect partial frame"
    let plan = recovery.plan.value
    assert plan.prefix.byteLength == original.len, "repair keeps exact authenticated prefix"
    assert plan.prefix.snapshot.bytes == retained.bytes, "repair keeps previous evidence"
    assert uint64(plan.prefix.sequence) == oldSequence, "repair preserves global predecessor sequence"
    assert recovery.repair(owner).error == FileError.None, "explicit synchronized prefix repair"
    assert readFile(lightChild(path, ManagedFileKind.Journal)) == original, "repair discards only incomplete suffix"
    assert owner.append(delta).error == FileError.None, "retry only after a fresh confirmed owner"
  else:
    # A complete frame is reauthenticated even if the child died before its application publication or barrier receipt.
    assert opened == FileError.None, "strict reopen confirms complete observed frame"
  assert owner.preparedSnapshot.value.bytes == delta.snapshot.bytes, "exact confirmed successor"
  assert uint64(owner.sequence.value) == oldSequence+1, "one confirmed sequence increment"
  assert owner.close == FileError.None, "explicit append owner retirement"
  assert retained.bytes == (if following: fixture.next.snapshot.bytes else: fixture.initial.bytes), "old readers remain immutable"
  assert readFile(path & "/KEEP") == "unselected forensic sentinel", "recovery preserves unknown forensic siblings"
  retireLightJournal(path)
proc lightBootstrapCrash*(fixture: LightJournalFixture, operation, skip: cint,
    shortWrites = false): uint64 {.raises.} =
  ## Every bootstrap boundary either leaves an exact unselected forensic prefix or a fully verifiable selected checkpoint/anchor.
  let path = "light-bootstrap-crash-" & $storageProcessId() & "-" & $operation & "-" &
      $skip & "-" & $shortWrites
  let manifest = prepareLightJournalManifest(fixture.initial, ManagedEpoch(1), LightDeltaSequence(
      0), ByteLimit(LightJournalManifestBytes)).value
  let anchor = encodeLightJournalAnchor(manifest, ByteLimit(LightJournalAnchorBytes)).value
  let snapshotBytes = lightText(fixture.initial.encodedBytes)
  let manifestBytes = lightText(manifest.bytes)
  let anchorBytes = lightText(anchor)
  var owner = default(LightJournalCache)
  var contender = default(LightJournalCache)
  defer:
    abortCrash()
    resetIo()
    if contender.opened: discard contender.close
    if owner.opened: discard owner.close
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0, "adopt one bootstrap child"
  if child == 0:
    # Start before namespace creation so lock/parent barriers and all file publication boundaries are observed.
    if shortWrites: limitWrites(64)
    if startCrash() != 0: exitCrash(82)
    if initializeLightJournalCache(owner, path, fixture.config, fixture.initial).error !=
        FileError.None: exitCrash(83)
    exitCrash(0)
  result = supervise(path, fixture, skip, contender)
  let names = ["CURRENT", "CURRENT.next", "snapshot-0000000000000001.bin",
      "journal-0000000000000001.wal", "LOCK"]
  var present = default(array[5, bool])
  var forensic = default(array[5, string])
  for index in 0..<names.len:
    # Capture every known namespace child before strict open can be assessed for forensic preservation.
    present[index] = exists(path & "/" & names[index])
    if present[index]: forensic[index] = readFile(path & "/" & names[index])
  assert present[4] and forensic[4].len == 0, "bootstrap retains its original regular empty LOCK"
  assert not (present[0] and present[1]), "bootstrap selects only by consuming CURRENT.next in rename"
  if present[2]: checkPrefix(forensic[2], snapshotBytes)
  if present[3]: checkPrefix(forensic[3], anchorBytes)
  if present[1]: checkPrefix(forensic[1], manifestBytes)
  if present[0]:
    # Selection is possible only after complete synchronized checkpoint/anchor and complete staged manifest bytes.
    assert forensic[0] == manifestBytes, "selected manifest is exact and complete"
    assert present[2] and forensic[2] == snapshotBytes, "selected checkpoint is complete"
    assert present[3] and forensic[3] == anchorBytes, "selected anchored journal is complete"
  if operation == writeIo and skip != 4096:
    # Both ordinary and short native writes have independently predicted per-file completed extents.
    let chunk = if shortWrites: 64 else: 4096
    let payloads = [snapshotBytes, anchorBytes, manifestBytes]
    let positions = [2, 3, 1]
    var remaining = int(result)
    for index in 0..<payloads.len:
      let count = min(remaining, (payloads[index].len+chunk-1) div chunk)
      remaining -= count
      assert present[positions[index]] == (count > 0), "future bootstrap files are not created before their first observed write"
      if count > 0:
        assert forensic[positions[index]].len == min(payloads[index].len, count*chunk), "exact successful per-file write extent"
    assert remaining == 0 and not present[0], "write stops precede manifest selection"
  let opened = openLightJournalCache(owner, path, fixture.config)
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0, "strict bootstrap reopen never adopts or cleans staging"
  for index in 0..<names.len:
    # Refused and successful strict opens preserve every exact known byte and presence observation.
    assert exists(path & "/" & names[index]) == present[index], "strict open preserves forensic presence"
    if present[index]: assert readFile(path & "/" & names[index]) == forensic[index], "strict open preserves forensic bytes"
  if present[0]:
    assert opened == FileError.None, "strict reopen confirms selected bootstrap"
    assert owner.preparedSnapshot.value.bytes == fixture.initial.bytes and uint64(
        owner.sequence.value) == 0, "exact initial selected evidence"
    assert owner.append(fixture.next).error == FileError.None, "selected bootstrap remains appendable"
    assert owner.close == FileError.None, "retire confirmed bootstrap"
  else:
    # An unselected failed namespace is preserved, never automatically adopted or overwritten by initialization.
    assert opened != FileError.None and not owner.opened, "missing CURRENT never triggers fallback"
    var lease = default(ManagedDirectory)
    assert openManagedDirectory(lease, path) == FileError.None, "refused strict open released every native lease"
    assert lease.close == FileError.None, "explicit forensic namespace lease retirement"
    let retry = path & "-retry"
    seedLightJournal(retry, fixture)
    assert openLightJournalCache(owner, retry, fixture.config) == FileError.None, "fresh explicit namespace bootstrap retry"
    assert owner.close == FileError.None, "retire retry namespace"
    retireLightJournal(retry)
  retireLightJournal(path)
