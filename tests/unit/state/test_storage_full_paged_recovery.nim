# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact independent full-graph replay bounds partial epoch/staging cleanup and bootstrap resumption.
# @@Verification={"arc":"storage_full_paged_recovery_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../support/state_full_paged_reference
import ../../support/state_full_paged_native_fixture
import ../../../src/storage/full_paged_codec as storage_full_paged_codec
import ../../../src/storage/full_paged_stream as storage_full_paged_stream
import ../../../src/storage/full_paged_build as storage_full_paged_build
import ../../../src/storage/full_paged_store as storage_full_paged_store
import ../../../src/storage/paged_io as storage_paged_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
proc path(label: string): string =
  ## Every scenario uses a fresh test-owned namespace, without database directory scans.
  "full-paged-recovery-" & $storageProcessId() & "-" & label
proc writePrefix(path: string, bytes: openArray[byte], count: int) =
  ## Independent oracle prefixes stop inside headers, records, digests and manifest checksums.
  var text = newString(count)
  for index in 0..<count: text[index] = char(bytes[index]) # The caller bounds every reference slice.
  try:
    writeFile(path, text)
  except:
    assert false, "write exact test prefix"
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Inspect one explicit test path; absence grants no namespace-wide cleanup authority.
proc exists(path: string): bool =
  ## Keep missing files distinct from actual zero-byte prefixes.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc cut(directory: string, target: FullPagedFixture, count: int, pending = 73) =
  ## Source-independent complete fixture bytes define both exact cleanup targets.
  writePrefix(directory & "/" & epochName(target.header.epoch).value, target.io.bytes, count)
  writePrefix(directory & "/CURRENT.next", target.manifest.bytes.value, pending)
proc replay(writer: var FullPagedWriter, candidate: var FullPagedCandidate,
    source: FullPagedManifest, target: FullPagedFixture): FullPagedNativeResult[bool] =
  ## Ordinary replacement reconstruction uses only caller-owned records and independent target metadata.
  prepareFullPagedCleanup(writer, candidate, source, target.header, target.records.producer)
proc prefixes(old, target: FullPagedFixture) =
  ## Exact short/full prefixes qualify; altered bytes, overlong staging and missing authority never do.
  for count in [0, 1, 4095, 4096, target.io.bytes.len-17, target.io.bytes.len]:
    let directory = path("prefix-" & $count)
    var writer = default(FullPagedWriter)
    var candidate = default(FullPagedCandidate)
    defer:
      if candidate.opened: discard candidate.close # Even an assertion failure retires owned resources.
      if writer.opened: discard writer.close
    writer.seed(directory, old)
    let source = writer.selected.value
    cut(directory, target, count)
    assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
    assert writer.publish(candidate).error == FullPagedNativeError.InvalidCandidate
    let removed = discardFullPagedCandidate(writer, candidate, source)
    assert removed.error == FullPagedNativeError.None and not candidate.opened
    assert removed.value.retirementError == FileError.None
    assert not exists(directory & "/" & epochName(target.header.epoch).value)
    assert not exists(directory & "/CURRENT.next")
    writer.prepare(candidate, target)
    assert writer.publish(candidate).error == FullPagedNativeError.None
    assert writer.close == FileError.None
proc refusals(old, target: FullPagedFixture) =
  ## Prefix mismatch, producer failure, policy refusal and late-created paths preserve all forensic files.
  for mode in 0..<8:
    let directory = path("refuse-" & $mode)
    var writer = default(FullPagedWriter)
    var candidate = default(FullPagedCandidate)
    defer:
      if candidate.opened: discard candidate.close # Failed capability checks never silently close native owners.
      if writer.opened: discard writer.close
    writer.seed(directory, old)
    let source = writer.selected.value
    var bytes = target.io.bytes
    var pending = target.manifest.bytes.value
    if mode == 0: bytes[31] = bytes[31] xor 1 # Header mismatch remains forensic.
    if mode == 1: pending[72] = pending[72] xor 1 # Staging mismatch preflights before epoch deletion.
    if mode < 2:
      writePrefix(directory & "/" & epochName(target.header.epoch).value, bytes, 4097)
      writePrefix(directory & "/CURRENT.next", pending, 73)
      assert writer.replay(candidate, source, target).error != FullPagedNativeError.None
      assert not candidate.opened
    elif mode == 2:
      # Captured epoch absence refuses an equal-position file created after preparation.
      assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
      writePrefix(directory & "/" & epochName(target.header.epoch).value, bytes, 0)
      assert discardFullPagedCandidate(writer, candidate, source).error ==
          FullPagedNativeError.StaleView
    elif mode == 3:
      # Captured staging absence similarly refuses a later unknown child.
      assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
      writePrefix(directory & "/CURRENT.next", pending, 0)
      assert discardFullPagedCandidate(writer, candidate, source).error != FullPagedNativeError.None
    elif mode == 4:
      # The default-deny replay disk budget refuses before authoring or capturing target authority.
      assert writer.close == FileError.None
      var config = old.config
      config.replayBytes = ByteLimit(target.io.bytes.len-1)
      assert openFullPagedWriter(writer, directory, config).error == FullPagedNativeError.None
      cut(directory, target, 4097)
      assert writer.replay(candidate, source, target).error == FullPagedNativeError.FileFailure
    elif mode == 5:
      # A same-generation target cannot substitute another complete root under compaction semantics.
      let wrong = target.reposition(ManagedEpoch(2), RepositoryGeneration(0))
      cut(directory, target, 4097)
      assert writer.replay(candidate, source, wrong).error != FullPagedNativeError.None
    elif mode == 6:
      # The full staging width rejects the light-format193-byte transport before prefix capture.
      cut(directory, target, 4097)
      var overlong = newSeq[byte](193)
      writePrefix(directory & "/CURRENT.next", overlong, overlong.len)
      assert writer.replay(candidate, source, target).error != FullPagedNativeError.None
    else:
      # A complete expected body cannot authorize even one additional forensic byte.
      bytes.add(0)
      writePrefix(directory & "/" & epochName(target.header.epoch).value, bytes, bytes.len)
      assert writer.replay(candidate, source, target).error != FullPagedNativeError.None
    assert writer.close == FileError.None
proc sealed(old, target: FullPagedFixture) =
  ## Complete live seals need no replay; a mismatched staging retry must never turn into deletion permission.
  let directory = path("sealed")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  defer:
    if candidate.opened: discard candidate.close # Keep test-owned descriptors explicitly retired.
    if writer.opened: discard writer.close
  writer.seed(directory, old)
  let source = writer.selected.value
  writer.prepare(candidate, target)
  var pending = target.manifest.bytes.value
  pending[0] = pending[0] xor 1
  writePrefix(directory & "/CURRENT.next", pending, 73)
  for attempt in 0..<2:
    # The first failed comparison retains its pin; the second still must validate exact bytes/version.
    assert discardFullPagedCandidate(writer, candidate, source).error != FullPagedNativeError.None
    assert exists(directory & "/" & epochName(target.header.epoch).value)
  assert candidate.close == FileError.None
  writePrefix(directory & "/CURRENT.next", target.manifest.bytes.value, 73)
  assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
  assert discardFullPagedCandidate(writer, candidate, source).error == FullPagedNativeError.None
  assert writer.close == FileError.None
proc compaction(old: FullPagedFixture) =
  ## Source-derived same-generation cleanup accepts no caller graph substitution and consumes no producer calls.
  let directory = path("compact")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  writer.seed(directory, old)
  let source = writer.selected.value
  let target = old.reposition(ManagedEpoch(2), RepositoryGeneration(0))
  cut(directory, target, 4097)
  assert prepareFullPagedCleanup(writer, candidate, source, target.header, nil).error ==
      FullPagedNativeError.None
  assert discardFullPagedCandidate(writer, candidate, source).error == FullPagedNativeError.None
  assert writer.close == FileError.None
proc faultTrial(old, target: FullPagedFixture, phase: int, operation: cint,
    skip: int): array[7, uint64] =
  ## Every observed preparation/removal fault fires; fresh strict reopen and replay finish only exact remaining prefixes.
  result = default(array[7, uint64])
  let directory = path("fault-" & $phase & "-" & $operation & "-" & $skip)
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  defer:
    resetIo() # Never let an assertion propagate an armed fault into unrelated teardown.
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  writer.seed(directory, old)
  let source = writer.selected.value
  cut(directory, target, target.io.bytes.len-17)
  if phase == 1:
    assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
  resetIo()
  if operation != 0: armIo(operation, cint(skip), 1, failedIo) # Schedule exactly one actual syscall refusal.
  if phase == 0:
    # Failed preparation exposes no cleanup capability or deletion prefix.
    let prepared = writer.replay(candidate, source, target)
    if operation == 0: assert prepared.error == FullPagedNativeError.None
    else: assert prepared.error != FullPagedNativeError.None and not candidate.opened
  else:
    # Post-confirmation close errors remain separate successful receipt diagnostics.
    let removed = discardFullPagedCandidate(writer, candidate, source)
    if operation == 0: assert removed.error == FullPagedNativeError.None
    elif removed.error == FullPagedNativeError.None:
      assert operation == closeIo and removed.value.retirementError == FileError.IoFailure
  if operation == 0:
    # Observe only the tested operation, excluding baseline selected-receipt reads and later teardown.
    result = [ioCalls(readIo), ioCalls(writeIo), ioCalls(lockIo), ioCalls(closeIo),
      ioCalls(syncIo), ioCalls(unlinkIo), ioCalls(truncateIo)]
  else: assert pendingIo() == 0 # An unconsumed injection cannot count as a passing failure witness.
  resetIo()
  if candidate.opened: assert candidate.close == FileError.None
  assert writer.close == FileError.None
  assert openFullPagedWriter(writer, directory, old.config).error == FullPagedNativeError.None
  assert writer.selected.value.bytes.value == source.bytes.value
  assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
  assert discardFullPagedCandidate(writer, candidate, source).error == FullPagedNativeError.None
  assert not exists(directory & "/CURRENT.next")
  assert writer.close == FileError.None
proc faults(old, target: FullPagedFixture) =
  ## Each syscall index is measured first; graph scratch and staging/epoch close failures are independently covered.
  let operations = [readIo, writeIo, lockIo, closeIo, syncIo, unlinkIo, truncateIo]
  for phase in 0..<2:
    let counts = faultTrial(old, target, phase, 0, 0)
    for index in 0..<operations.len:
      # Absent operations are not fabricated; actual schedules remain finite and reproducible.
      assert counts[index] < 2000
      for skip in 0..<int(counts[index]): discard faultTrial(old, target, phase, operations[index], skip)
proc bootstrap(old: FullPagedFixture) =
  ## Write/rename interruption resumes only an existing LOCK with absent CURRENT and exact fresh replay.
  for operation in [writeIo, renameIo]:
    let directory = path("bootstrap-" & $operation)
    var writer = default(FullPagedWriter)
    defer:
      resetIo() # Failure injection never leaks beyond this bootstrap trial.
      if writer.opened: discard writer.close
    resetIo()
    armIo(operation, 0, 1, failedIo)
    let failed = initializeFullPagedWriter(writer, directory, old.config, old.roots,
      old.records.producer, old.header.geometry.entries, old.header.geometry.payloadBytes)
    assert failed.error != FullPagedNativeError.None and pendingIo() == 0
    resetIo()
    assert writer.close == FileError.None
    let resumed = resumeFullPagedInitialization(writer, directory, old.config, old.roots,
      old.records.producer, old.header.geometry.entries, old.header.geometry.payloadBytes)
    assert resumed.error == FullPagedNativeError.None and resumed.value.writerUsable
    assert writer.close == FileError.None
    # Any existing selection, including a malformed empty CURRENT, blocks recovery without deleting epoch1.
    writePrefix(directory & "/CURRENT", @[], 0)
    let refused = resumeFullPagedInitialization(writer, directory, old.config, old.roots,
      old.records.producer, old.header.geometry.entries, old.header.geometry.payloadBytes)
    assert refused.error != FullPagedNativeError.None
    assert exists(directory & "/" & epochName(ManagedEpoch(1)).value)
    assert writer.close == FileError.None
proc stale(old, target: FullPagedFixture) =
  ## Reopened writers cannot consume a prior incarnation's capability, even at the same exact source head.
  let directory = path("incarnation")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  writer.seed(directory, old)
  let source = writer.selected.value
  cut(directory, target, 4097)
  assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
  assert writer.close == FileError.None
  assert openFullPagedWriter(writer, directory, old.config).error == FullPagedNativeError.None
  assert discardFullPagedCandidate(writer, candidate, source).error ==
      FullPagedNativeError.StaleView
  assert candidate.close == FileError.None
  assert writer.replay(candidate, default(FullPagedManifest), target).error ==
      FullPagedNativeError.StaleView
  assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
  assert discardFullPagedCandidate(writer, candidate, source).error == FullPagedNativeError.None
  assert writer.close == FileError.None
proc changedBootstrap(old: FullPagedFixture) =
  ## Fresh construction after successful replay may not publish a failed or changed producer stream.
  let directory = path("changed-bootstrap")
  var owner = default(PagedDirectory)
  assert openDirectory(owner, directory, true, true) == FileError.None
  assert owner.close == FileError.None
  cut(directory, old, 4097)
  var calls = 0
  proc changing(pass: int, ordinal: uint64, output: var TrieRecord): FullPagedProducerStep {.closure.} =
    ## Replay has exactly two complete ordinal/end passes; any subsequent producer operation refuses.
    inc calls
    if calls > (old.records.len+1)*2: return FullPagedProducerStep.Failed
    if ordinal >= uint64(old.records.len): return FullPagedProducerStep.End
    output = old.records[int(ordinal)]
    FullPagedProducerStep.Item
  var writer = default(FullPagedWriter)
  let resumed = resumeFullPagedInitialization(writer, directory, old.config, old.roots,
    changing, old.header.geometry.entries, old.header.geometry.payloadBytes)
  assert resumed.error != FullPagedNativeError.None and calls > (old.records.len+1)*2
  assert not exists(directory & "/CURRENT")
  assert writer.close == FileError.None
proc main() =
  ## Independent roots/oracle bytes, real native faults and repeated retirements qualify explicit full recovery.
  let old = historySample(5, 7)
  let target = historySample(7, 9).reposition(ManagedEpoch(2), RepositoryGeneration(1))
  prefixes(old, target)
  refusals(old, target)
  sealed(old, target)
  compaction(old)
  faults(old, target)
  bootstrap(old)
  stale(old, target)
  changedBootstrap(old)
  let directory = path("cycles")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  writer.seed(directory, old)
  let source = writer.selected.value
  assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
  assert discardFullPagedCandidate(writer, candidate, source).error == FullPagedNativeError.None
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # No resident replay graph or native pin survives a successful captured-absence cleanup cycle.
    assert writer.replay(candidate, source, target).error == FullPagedNativeError.None
    assert discardFullPagedCandidate(writer, candidate, source).error == FullPagedNativeError.None
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_recovery", 1000, before, after)
  assert writer.close == FileError.None
  echo "storage full paged recovery PASS"
main()
