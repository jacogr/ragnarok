# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real successful syscall stops qualify paged publication, explicit replay recovery and exact retired-epoch cleanup.
import std/[assertions, syncio, envvars]
import ../../support/[paged_native_fixture, paged_reference, storage_io, storage_crash]
import ../../../src/storage/paged/[store as paged_store, io as paged_io, codec as paged_codec,
    stream as paged_stream]
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/light/delta as light_delta
import ../../../src/storage/file/errors as file_errors
import ../../../src/storage/light/state_cache as light_state_cache
import ../../../src/storage/state_proof
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Observe only fixed test-owned names; discovery never grants recovery authority.
proc exists(path: string): bool =
  ## Absence remains distinct from a created zero-byte artifact.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc text(bytes: seq[byte]): string =
  ## Fixture-sized independent oracle bytes may be resident only in these tests.
  result = newString(bytes.len)
  for index, value in bytes: result[index] = char(value)
proc prefix(path, expected: string) {.raises.} =
  ## Interrupted files must be absent or exact bounded prefixes of independently authored bytes.
  if not exists(path): return
  let actual = readFile(path)
  assert actual.len <= expected.len
  for index in 0..<actual.len: assert actual[index] == expected[index]
proc capture(path: string): seq[string] {.raises.} =
  ## Strict reopen must preserve all known names and their complete forensic bytes.
  result = @[]
  for name in ["CURRENT", "CURRENT.next", "LOCK", "KEEP", "paged-0000000000000001.bin",
      "paged-0000000000000002.bin"]:
    let child = path & "/" & name
    result.add(if exists(child): "present:" & readFile(child) else: "absent")
proc prepare(writer: var PagedWriter, candidate: var PagedCandidate, mode: int,
    target: PagedNativeFixture) =
  ## The selected operation controls sequence semantics; callers supply independently trusted destination proofs.
  let checked = if mode == 2:
      preparePagedAdvance(writer, candidate, target.config.root, target.records.nativeProducer,
        uint64(target.records.len), target.payload)
    elif mode == 3: preparePagedCompaction(writer, candidate)
    else: preparePagedReplacement(writer, candidate, target.records.nativeProducer,
        uint64(target.records.len), target.payload)
  assert checked.error == PagedNativeError.None
proc trial(old, fresh: PagedNativeFixture, mode: int, operation, skip: cint,
    chunk: int): uint64 {.raises.} =
  ## Every trial owns one exact child and namespace; the parent releases its writer before fork.
  let path = "paged-crash-" & $storageProcessId() & "-" & $mode & "-" & $operation & "-" &
    $skip & "-" & $chunk
  let initial = mode == 0 or mode == 5
  let target = if mode == 2: fresh else: old
  let epoch = if initial: 1'u64 else: 2'u64
  let sequence = if mode == 1 or mode == 4 or mode == 6: 1'u64 else: 0'u64
  var oracle = pagedReference(target.config.chain, target.config.root, target.records)
  oracle.bytes.put(88, epoch)
  oracle.bytes.put(96, sequence)
  oracle.recommit()
  let image = text(oracle.bytes)
  let manifest = text(oracle.manifest)
  let targetName = path & "/" & epochName(ManagedEpoch(epoch)).value
  let header = initPagedHeader(target.config.chain, target.config.root, ManagedEpoch(epoch),
      LightDeltaSequence(sequence), uint64(target.records.len), target.payload,
      target.config.limits.dataset).value
  var writer = default(PagedWriter)
  var contender = default(PagedWriter)
  var candidate = default(PagedCandidate)
  var retained = default(PagedReader)
  var receipt = default(PagedEpochReceipt)
  var source = default(PagedManifest)
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
    assert initializePagedWriter(writer, path, old.config, old.records.nativeProducer,
      uint64(old.records.len), old.payload).error == PagedNativeError.None
    source = writer.selected.value
    oldCurrent = readFile(path & "/CURRENT")
    oldImage = readFile(path & "/paged-0000000000000001.bin")
    assert openPagedReader(retained, path, old.config).error == PagedNativeError.None
    receipt = retained.epochReceipt.value
    if mode == 6:
      # Reclamation requires retirement of the independently owned source reader before its exclusive pin.
      assert retained.close == FileError.None
      prepare(writer, candidate, 1, target)
      assert writer.publish(candidate).error == PagedNativeError.None
    elif mode == 4:
      # Independent partial artifact and checksum staging bytes constrain explicit replay cleanup.
      writeFile(targetName, image[0..<4097])
      writeFile(path & "/CURRENT.next", manifest[0..<73])
    assert writer.close == FileError.None
    writeFile(path & "/KEEP", "preserved paged crash sibling")
  elif mode == 5:
    # A real bootstrap rename refusal leaves an existing LOCK and completely authored replayable files.
    resetIo()
    armIo(renameIo, 0, 1, failedIo)
    assert initializePagedWriter(writer, path, old.config, old.records.nativeProducer,
      uint64(old.records.len), old.payload).error != PagedNativeError.None
    assert pendingIo() == 0
    resetIo()
    assert writer.close == FileError.None
    writeFile(path & "/KEEP", "preserved paged crash sibling")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    # Fixture construction and ordinary strict reopen are outside the armed syscall schedule.
    if not initial:
      if openPagedWriter(writer, path, (if mode == 6: target.config else: old.config)).error !=
          PagedNativeError.None: exitCrash(81)
    if chunk > 0: limitWrites(csize_t(chunk))
    if startCrash() != 0: exitCrash(82)
    if mode == 0:
      if initializePagedWriter(writer, path, old.config, old.records.nativeProducer,
          uint64(old.records.len), old.payload).error != PagedNativeError.None: exitCrash(83)
    elif mode == 5:
      if resumePagedInitialization(writer, path, old.config, old.records.nativeProducer,
          uint64(old.records.len), old.payload).error != PagedNativeError.None: exitCrash(84)
    elif mode == 4:
      if preparePagedCleanup(writer, candidate, source, header, old.records.nativeProducer).error !=
          PagedNativeError.None: exitCrash(85)
      if discardPagedCandidate(writer, candidate, source).error != PagedNativeError.None: exitCrash(86)
    elif mode == 6:
      if writer.reclaim(receipt, writer.selected.value).error != PagedNativeError.None: exitCrash(87)
    else:
      # Replacement, independently trusted root advancement and exact-source compaction share publication.
      prepare(writer, candidate, mode, target)
      if writer.publish(candidate).error != PagedNativeError.None: exitCrash(88)
    exitCrash(0)
  if skip != 4096:
    # A real stopped child still holds its writer lease, including bootstrap before CURRENT exists.
    assert waitCrash() == crashStopped
    assert openPagedWriter(contender, path, old.config).fileError == FileError.Busy
    assert not contender.opened
  let outcome = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert outcome == crashCompleted and result > 0 and result < 4096
  else:
    assert outcome == crashKilled and result == uint64(skip)+1
  resetIo()
  let selected = if exists(path & "/CURRENT"): readFile(path & "/CURRENT") else: ""
  let newSelected = selected == manifest
  assert selected == oldCurrent or newSelected
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
    assert openPagedWriter(writer, path, wrong.config).error != PagedNativeError.None
    assert not writer.opened and capture(path) == before
    resetIo()
    assert openPagedWriter(writer, path, expected.config).error == PagedNativeError.None
    assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0 and ioCalls(unlinkIo) == 0
    assert capture(path) == before
    if not newSelected:
      # Every interrupted prefix is recovered only by fresh complete independent replay, then original authoring.
      assert preparePagedCleanup(writer, candidate, source, header,
        target.records.nativeProducer).error == PagedNativeError.None
      assert discardPagedCandidate(writer, candidate, source).error == PagedNativeError.None
      assert not exists(targetName) and not exists(path & "/CURRENT.next")
      prepare(writer, candidate, if mode == 4: 1 else: mode, target)
      assert writer.publish(candidate).error == PagedNativeError.None
    elif mode == 6:
      # Already-absent retirement still has to synchronize the directory on retry.
      resetIo()
      assert writer.reclaim(receipt, writer.selected.value).error == PagedNativeError.None
      assert ioCalls(syncIo) > 0
    assert writer.selected.value.bytes == oracle.manifest
    assert writer.close == FileError.None
  else:
    # Only explicit initialization resume can advance an interrupted bootstrap with absent CURRENT.
    assert initial and capture(path) == before
    assert resumePagedInitialization(writer, path, old.config, old.records.nativeProducer,
      uint64(old.records.len), old.payload).error == PagedNativeError.None
    assert writer.selected.value.bytes == oracle.manifest
    assert writer.close == FileError.None
  var current = default(PagedReader)
  assert openPagedReader(current, path, target.config).error == PagedNativeError.None
  assert current.lookup(pagedKey(0), target.config.limits.work).value.bytes[0] ==
    (if mode == 2: 9'u8 else: 7'u8)
  assert current.lookup(pagedKey(128), target.config.limits.work).value.bytes.len == 0
  assert current.lookup(pagedKey(255), target.config.limits.work).value.kind ==
      StateLookupKind.Absent
  assert current.lookup(pagedKey(32), target.config.limits.work).error ==
      PagedNativeError.UnknownKey
  assert current.close == FileError.None
  if retained.opened:
    assert retained.lookup(pagedKey(0), old.config.limits.work).value.bytes[0] == 7
    assert retained.selected.value.bytes == source.bytes
    assert retained.close == FileError.None
  if mode != 0: assert readFile(path & "/KEEP") == "preserved paged crash sibling"
proc main() {.raises.} =
  ## Positive completion controls measure genuine operations; every observed successful boundary gets an exact kill trial.
  let old = nativeFixture(7)
  let fresh = nativeFixture(9)
  var controls = 0
  var deaths = 0
  for mode in 0..6:
    let operations = if mode == 4: @[writeIo, syncIo, unlinkIo, closeIo]
      elif mode == 6: @[syncIo, unlinkIo, closeIo]
      elif mode == 5: @[writeIo, syncIo, unlinkIo, renameIo, closeIo]
      else: @[writeIo, syncIo, renameIo, closeIo]
    for operation in operations:
      let count = trial(old, fresh, mode, operation, 4096, 0)
      assert count > 0 and count < 128
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
  assert controls == 32 and deaths > controls
  let evidence = getEnv("RAGNAROK_TEST_EVIDENCE")
  if evidence.len > 0:
    writeFile(evidence & "/storage_paged_crashes.json", "{\"controls\":" & $controls &
      ",\"killed_boundaries\":" & $deaths & "}\n")
try:
  main()
except:
  quit(2)
echo "PASS paged crashes: exact stopped-child deaths, independent selection bytes, explicit replay and retained readers"
