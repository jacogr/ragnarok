# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real successful syscall stops qualify complete full-graph publication, explicit replay recovery and exact retired-epoch cleanup.
import std/[assertions, syncio, envvars]
import ../../support/[full_paged_native_fixture, full_paged_reference, storage_io, storage_crash]
import ../../../src/storage/[full_paged_store, paged_io, full_paged_codec, full_paged_stream,
  managed_manifest, node_repository, file_errors]
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Observe only fixed test-owned names; discovery never grants recovery authority.
proc exists(path: string): bool =
  ## Absence remains distinct from a created zero-byte artifact.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc text(bytes: openArray[byte]): string =
  ## Fixture-sized independent oracle bytes may be resident only in these tests.
  result = newString(bytes.len)
  for index, value in bytes: result[index] = char(value)
proc prefix(path, expected: string) {.raises.} =
  ## Interrupted files must be absent or exact bounded prefixes of independently authored bytes.
  if not exists(path): return
  let actual = readFile(path)
  assert actual.len <= expected.len, "prefix extent " & path
  for index in 0..<actual.len: assert actual[index] == expected[index], "prefix byte " & path &
      " " & $index
proc capture(path: string): seq[string] {.raises.} =
  ## Strict reopen must preserve all known names and their complete forensic bytes.
  result = @[]
  for name in ["CURRENT", "CURRENT.next", "LOCK", "KEEP", "paged-0000000000000001.bin",
      "paged-0000000000000002.bin"]:
    let child = path & "/" & name
    result.add(if exists(child): "present:" & readFile(child) else: "absent")
proc prepare(writer: var FullPagedWriter, candidate: var FullPagedCandidate, mode: int,
    target: FullPagedFixture) =
  ## Source-derived compaction preserves generation; all complete replacements advance once with explicit root inventory.
  let checked = if mode == 3: prepareFullPagedCompaction(writer, candidate)
    else: prepareFullPagedReplacement(writer, candidate, target.header.root, target.roots,
      target.records.producer, uint64(target.records.len), target.header.geometry.payloadBytes)
  assert checked.error == FullPagedNativeError.None
proc trial(old, fresh: FullPagedFixture, mode: int, operation, skip: cint,
    chunk: int): uint64 {.raises.} =
  ## Every trial owns one exact child and namespace; the parent releases its writer before fork.
  if getEnv("RAGNAROK_CRASH_TRACE") == "1":
    # Optional diagnostics identify an exact native death boundary without weakening the normal output contract.
    echo "trial ", mode, " ", operation, " ", skip, " ", chunk
  let path = "full-paged-crash-" & $storageProcessId() & "-" & $mode & "-" & $operation & "-" &
    $skip & "-" & $chunk
  let initial = mode == 0 or mode == 5
  let target = if mode == 2: fresh else: old
  let epoch = if initial: 1'u64 else: 2'u64
  let generation = if mode == 1 or mode == 2 or mode == 4 or mode == 6: 1'u64 else: 0'u64
  let oracle = target.reposition(ManagedEpoch(epoch), RepositoryGeneration(generation))
  let image = text(oracle.io.bytes)
  let manifest = text(oracle.manifest.bytes.value)
  let targetName = path & "/" & epochName(ManagedEpoch(epoch)).value
  let header = oracle.header
  var writer = default(FullPagedWriter)
  var contender = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  var retained = default(FullPagedReader)
  var receipt = default(FullPagedEpochReceipt)
  var source = default(FullPagedManifest)
  var oldCurrent = ""
  var oldImage = ""
  defer:
    abortCrash()
    resetIo()
    if candidate.opened: discard candidate.close
    if retained.opened: discard retained.close
    if contender.opened: discard contender.close
    if writer.opened: discard writer.close
  if not initial:
    # A confirmed source and independent reader precede every steady-state crash operation.
    assert initializeFullPagedWriter(writer, path, old.config, old.roots, old.records.producer,
      uint64(old.records.len), old.header.geometry.payloadBytes).error == FullPagedNativeError.None
    source = writer.selected.value
    oldCurrent = readFile(path & "/CURRENT")
    oldImage = readFile(path & "/paged-0000000000000001.bin")
    assert openFullPagedReader(retained, path, old.config).error == FullPagedNativeError.None
    receipt = retained.epochReceipt.value
    if mode == 6:
      # Reclamation requires retirement of the independently owned source reader before its exclusive pin.
      assert retained.close == FileError.None
      prepare(writer, candidate, 1, target)
      assert writer.publish(candidate).error == FullPagedNativeError.None
    elif mode == 4:
      # Independent partial artifact and checksum staging bytes constrain explicit replay cleanup.
      writeFile(targetName, image[0..<4097])
      writeFile(path & "/CURRENT.next", manifest[0..<73])
    assert writer.close == FileError.None
    writeFile(path & "/KEEP", "preserved full paged crash sibling")
  elif mode == 5:
    # A real bootstrap rename refusal leaves an existing LOCK and completely authored replayable files.
    resetIo()
    armIo(renameIo, 0, 1, failedIo)
    assert initializeFullPagedWriter(writer, path, old.config, old.roots, old.records.producer,
      uint64(old.records.len), old.header.geometry.payloadBytes).error != FullPagedNativeError.None
    assert pendingIo() == 0
    resetIo()
    assert writer.close == FileError.None
    writeFile(path & "/KEEP", "preserved full paged crash sibling")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    # Fixture construction and ordinary strict reopen are outside the armed syscall schedule.
    if not initial:
      if openFullPagedWriter(writer, path, (if mode == 6: target.config else: old.config)).error !=
          FullPagedNativeError.None: exitCrash(81)
    if chunk > 0: limitWrites(csize_t(chunk))
    if startCrash() != 0: exitCrash(82)
    if mode == 0:
      if initializeFullPagedWriter(writer, path, old.config, old.roots, old.records.producer,
          uint64(old.records.len), old.header.geometry.payloadBytes).error !=
              FullPagedNativeError.None: exitCrash(83)
    elif mode == 5:
      if resumeFullPagedInitialization(writer, path, old.config, old.roots, old.records.producer,
          uint64(old.records.len), old.header.geometry.payloadBytes).error !=
              FullPagedNativeError.None: exitCrash(84)
    elif mode == 4:
      if prepareFullPagedCleanup(writer, candidate, source, header, old.records.producer).error !=
          FullPagedNativeError.None: exitCrash(85)
      if discardFullPagedCandidate(writer, candidate, source).error !=
          FullPagedNativeError.None: exitCrash(86)
    elif mode == 6:
      if writer.reclaim(receipt, writer.selected.value).error !=
          FullPagedNativeError.None: exitCrash(87)
    else:
      # Replacement, independently trusted root advancement and exact-source compaction share publication.
      prepare(writer, candidate, mode, target)
      if writer.publish(candidate).error != FullPagedNativeError.None: exitCrash(88)
    exitCrash(0)
  if skip != 4096:
    # A real stopped child still holds its writer lease, including bootstrap before CURRENT exists.
    assert waitCrash() == crashStopped
    assert openFullPagedWriter(contender, path, old.config).fileError == FileError.Busy
    assert not contender.opened
  let outcome = finishCrash()
  result = crashCount()
  if getEnv("RAGNAROK_CRASH_TRACE") == "1":
    # Surface supervision status before any higher-level artifact assertion.
    echo "child outcome ", outcome, " count ", result
  if skip == 4096:
    assert outcome == crashCompleted and result > 0 and result < 4096, "positive child control"
  else:
    assert outcome == crashKilled and result == uint64(skip)+1
  resetIo()
  let selected = if exists(path & "/CURRENT"): readFile(path & "/CURRENT") else: ""
  let newSelected = selected == manifest
  if getEnv("RAGNAROK_CRASH_TRACE") == "1":
    # Separate exact CURRENT identity failures from independent target-body comparison.
    echo "selected bytes ", selected.len, " expected ", manifest.len, " new ", newSelected
  assert selected == oldCurrent or newSelected, "CURRENT old or new"
  if mode == 4: assert not newSelected
  if mode == 6: assert newSelected
  prefix(targetName, image)
  prefix(path & "/CURRENT.next", manifest)
  if mode == 6:
    # Reclamation can only remove the exact old file; any survivor retains every original byte.
    let name = path & "/paged-0000000000000001.bin"
    if exists(name): assert readFile(name) == oldImage
  elif not initial:
    assert readFile(path & "/paged-0000000000000001.bin") == oldImage
  if newSelected:
    assert readFile(targetName) == image and not exists(path & "/CURRENT.next")
  let before = capture(path)
  if selected.len > 0:
    # The opposite independent root refuses; strict correct reopen performs no repair or namespace mutation.
    let expected = if newSelected: target else: old
    let wrong = if mode == 2 and newSelected: old else: fresh
    assert openFullPagedWriter(writer, path, wrong.config).error != FullPagedNativeError.None
    assert not writer.opened and capture(path) == before
    resetIo()
    assert openFullPagedWriter(writer, path, expected.config).error == FullPagedNativeError.None
    # Full graph admission writes only private anonymous membership scratch; fixed namespace bytes must stay identical.
    assert ioCalls(writeIo) > 0 and ioCalls(renameIo) == 0 and ioCalls(unlinkIo) == 0
    assert capture(path) == before
    if not newSelected:
      # Every interrupted prefix is recovered only by fresh complete independent replay, then original authoring.
      assert prepareFullPagedCleanup(writer, candidate, source, header,
        target.records.producer).error == FullPagedNativeError.None
      assert discardFullPagedCandidate(writer, candidate, source).error == FullPagedNativeError.None
      assert not exists(targetName) and not exists(path & "/CURRENT.next")
      prepare(writer, candidate, if mode == 4: 1 else: mode, target)
      assert writer.publish(candidate).error == FullPagedNativeError.None
    elif mode == 6:
      # Already-absent retirement still has to synchronize the directory on retry.
      resetIo()
      assert writer.reclaim(receipt, writer.selected.value).error == FullPagedNativeError.None
      assert ioCalls(syncIo) > 0
    assert writer.selected.value.bytes.value == oracle.manifest.bytes.value
    assert writer.close == FileError.None
  else:
    # Only explicit initialization resume can advance an interrupted bootstrap with absent CURRENT.
    assert initial and capture(path) == before
    assert resumeFullPagedInitialization(writer, path, old.config, old.roots, old.records.producer,
      uint64(old.records.len), old.header.geometry.payloadBytes).error == FullPagedNativeError.None
    assert writer.selected.value.bytes.value == oracle.manifest.bytes.value
    assert writer.close == FileError.None
  var current = default(FullPagedReader)
  assert openFullPagedReader(current, path, target.config).error == FullPagedNativeError.None
  assert current.lookup(target.header.root, key(0)).value.bytes[0] ==
    (if mode == 2: 9'u8 else: 7'u8)
  assert current.lookup(target.header.root, key(128)).value.bytes.len == 0
  assert not current.lookup(target.header.root, key(255)).value.present
  assert not current.lookup(target.header.root, key(32)).value.present
  assert current.close == FileError.None
  if retained.opened:
    assert retained.lookup(old.header.root, key(0)).value.bytes[0] == 7
    assert retained.selected.value.bytes.value == source.bytes.value
    assert retained.close == FileError.None
  if mode != 0: assert readFile(path & "/KEEP") == "preserved full paged crash sibling"
proc main() {.raises.} =
  ## Positive completion controls measure genuine operations; every observed successful boundary gets an exact kill trial.
  let old = sample(7)
  let fresh = sample(9)
  var controls = 0
  var deaths = 0
  for mode in 0..6:
    let operations = if mode == 4: @[writeIo, syncIo, unlinkIo, closeIo, truncateIo]
      elif mode == 6: @[syncIo, unlinkIo, closeIo, truncateIo]
      elif mode == 5: @[writeIo, syncIo, unlinkIo, renameIo, closeIo, truncateIo]
      else: @[writeIo, syncIo, renameIo, closeIo, truncateIo]
    for operation in operations:
      let count = trial(old, fresh, mode, operation, 4096, 0)
      assert count > 0 and count < 128, "bounded control schedule"
      controls += 1
      for skip in 0..<int(count):
        discard trial(old, fresh, mode, operation, cint(skip), 0)
        deaths += 1
    if mode == 0 or mode == 1 or mode == 2 or mode == 3:
      # Real short writes stop within page bodies and digest words as well as ordinary whole-write boundaries.
      let count = trial(old, fresh, mode, writeIo, 4096, 1024)
      assert count > 1 and count < 128
      controls += 1
      for skip in 0..<int(count):
        discard trial(old, fresh, mode, writeIo, cint(skip), 1024)
        deaths += 1
  assert controls == 39 and deaths > controls
  let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
  if evidence.len > 0:
    writeFile(evidence & "/storage_full_paged_crashes.json", "{\"controls\":" & $controls &
      ",\"killed_boundaries\":" & $deaths & "}\n")
try:
  main()
except:
  quit(2)
echo "PASS full paged crashes: exact stopped-child deaths, independent selection bytes, explicit replay and retained readers"
