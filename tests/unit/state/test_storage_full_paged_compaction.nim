# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full physical compaction preserves exact complete-root history and ordinary generation without a caller producer.
# @@Verification={"arc":"storage_full_paged_compaction_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, full_paged_reference, full_paged_native_fixture]
import ../../../src/storage/[full_paged_codec, full_paged_stream, full_paged_build, full_paged_store,
  paged_codec, paged_stream, paged_io, managed_manifest, node_repository, file_errors]
import ../../../src/codec/bounded
proc path(label: string): string =
  ## Process-specific names isolate every authored artifact and forensic prefix beneath the ignored native runner.
  "full-paged-compaction-" & $storageProcessId() & "-" & label
proc text(bytes: openArray[byte]): string =
  ## Independent full-file comparisons are test-only; production uses authenticated bounded pages.
  result = newString(bytes.len)
  for index in 0..<bytes.len: result[index] = char(bytes[index]) # Exact reference representation.
proc read(path: string): string =
  ## Bounded fixture files can be inspected directly outside native fault observation.
  try:
    result = readFile(path)
  except:
    assert false, "compaction fixture read failed"
proc output(io: FullPagedTestIO): PagedOutput =
  ## Resident output belongs only to the independent core compaction test fixture.
  proc append(bytes: openArray[byte]): bool {.closure.} =
    ## All-or-failure append never reorders or retains a borrowed page.
    for octet in bytes: io.bytes.add(octet) # Test-only materialized artifact.
    true
  PagedOutput(source: io.input, append: append)
func budget(): FullPagedCompactionLimits =
  ## Separate finite construction channels include all source-page authentication and target-tree work.
  FullPagedCompactionLimits(ioCalls: ElementLimit(100000), hashes: ElementLimit(100000),
    readBytes: ByteLimit(10000000), writeBytes: ByteLimit(1000000))
proc core(source: FullPagedFixture, cache: int) =
  ## Complete independent source/target byte oracles constrain exact copied history and all work channels.
  let admitted = source.check(policy(cache))
  assert admitted.error == FullPagedStreamError.None
  let expected = source.reposition(ManagedEpoch(2), RepositoryGeneration(0))
  let bytes = FullPagedTestIO()
  let built = compactFullPaged(bytes.output, source.io.input,
    FullPagedTestIO(bytes: newSeq[byte](source.records.len*2)).scratch,
    admitted.value, expected.header, budget())
  assert built.error == FullPagedBuildError.None and built.value.producerCalls == 0
  assert bytes.bytes == expected.io.bytes
  assert array[32, byte](built.value.checked.fingerprint) == array[32, byte](admitted.value.fingerprint)
  let observed = built.value
  var exact = budget()
  exact.ioCalls = ElementLimit(observed.ioCalls)
  exact.hashes = ElementLimit(observed.hashes)
  exact.readBytes = ByteLimit(observed.readBytes)
  exact.writeBytes = ByteLimit(observed.writeBytes)
  assert compactFullPaged(FullPagedTestIO().output, source.io.input,
    FullPagedTestIO(bytes: newSeq[byte](source.records.len*2)).scratch,
    admitted.value, expected.header, exact).error == FullPagedBuildError.None
  for channel in 0..3:
    # One-short global quotas include source authentication rather than resetting allowances per copied page.
    var short = exact
    case channel
    of 0: short.ioCalls = ElementLimit(observed.ioCalls-1)
    of 1: short.hashes = ElementLimit(observed.hashes-1)
    of 2: short.readBytes = ByteLimit(observed.readBytes-1)
    else: short.writeBytes = ByteLimit(observed.writeBytes-1)
    assert compactFullPaged(FullPagedTestIO().output, source.io.input,
      FullPagedTestIO(bytes: newSeq[byte](source.records.len*2)).scratch,
      admitted.value, expected.header, short).error == FullPagedBuildError.LimitExceeded
  for mode in 0..1:
    # Changed ordinary generation or skipped physical epoch refuses before any output byte.
    let changed = source.reposition(ManagedEpoch(if mode == 0: 2'u64 else: 3'u64),
      RepositoryGeneration(if mode == 0: 1'u64 else: 0'u64))
    let destination = FullPagedTestIO()
    assert compactFullPaged(destination.output, source.io.input,
      FullPagedTestIO(bytes: newSeq[byte](source.records.len*2)).scratch,
      admitted.value, changed.header, budget()).error == FullPagedBuildError.ChangedInput
    assert destination.bytes.len == 0
  let corrupt = FullPagedTestIO(bytes: clone(source.io.bytes))
  corrupt.bytes[4096] = corrupt.bytes[4096] xor 1
  assert compactFullPaged(FullPagedTestIO().output, corrupt.input,
    FullPagedTestIO(bytes: newSeq[byte](source.records.len*2)).scratch,
    admitted.value, expected.header, budget()).error == FullPagedBuildError.GraphFailure
proc normal(source: FullPagedFixture) =
  ## Published compaction matches every independent target byte while preserving retained roots and old pinned readers.
  let directory = path("normal")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  var reader = default(FullPagedReader)
  var newer = default(FullPagedReader)
  defer:
    if newer.opened: discard newer.close
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  writer.seed(directory, source)
  assert openFullPagedReader(reader, directory, source.config).error == FullPagedNativeError.None
  let receipt = reader.epochReceipt.value
  assert prepareFullPagedCompaction(writer, candidate).error == FullPagedNativeError.None
  let expected = source.reposition(ManagedEpoch(2), RepositoryGeneration(0))
  assert read(directory & "/" & epochName(ManagedEpoch(2)).value) == text(expected.io.bytes)
  let published = writer.publish(candidate)
  assert published.error == FullPagedNativeError.None and published.value.writerUsable
  assert uint64(published.value.manifest.generation) == 0
  assert read(directory & "/CURRENT") == text(expected.manifest.bytes.value)
  assert openFullPagedReader(newer, directory, source.config).error == FullPagedNativeError.None
  for index in 0..<source.header.len:
    # Every complete historical root remains admitted after the physical rewrite.
    let root = source.header.retainedRoot(index).root
    assert reader.lookup(root, key(0)).value.bytes == newer.lookup(root, key(0)).value.bytes
  let busy = writer.reclaim(receipt, writer.selected.value)
  assert busy.error == FullPagedNativeError.FileFailure and busy.fileError == FileError.Busy
  assert reader.close == FileError.None
  assert writer.reclaim(receipt, writer.selected.value).error == FullPagedNativeError.None
proc maxGeneration(source: FullPagedFixture) =
  ## Exhausted ordinary generation still permits exact compaction, including a zero producer allowance.
  let original = source.reposition(ManagedEpoch(1), RepositoryGeneration(high(uint64)))
  let expected = source.reposition(ManagedEpoch(2), RepositoryGeneration(high(uint64)))
  let directory = path("max-generation")
  seedOracle(directory, original)
  var config = source.config
  config.construction.producerCalls = ElementLimit(0)
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  defer:
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  assert openFullPagedWriter(writer, directory, config).error == FullPagedNativeError.None
  assert prepareFullPagedCompaction(writer, candidate).error == FullPagedNativeError.None
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert uint64(writer.selected.value.generation) == high(uint64)
  assert read(directory & "/" & epochName(ManagedEpoch(2)).value) == text(expected.io.bytes)
proc faultSchedule(source: FullPagedFixture) =
  ## Every preparation syscall refusal returns no sealed target authority and keeps strict selected-source recovery intact.
  let operations = [readIo, writeIo, syncIo, lockIo, truncateIo, closeIo]
  var counts = default(array[6, uint64])
  block baseline:
    # Capture exact compaction preparation only, after independent source bootstrap.
    var writer = default(FullPagedWriter)
    var candidate = default(FullPagedCandidate)
    writer.seed(path("fault-control"), source)
    resetIo()
    assert prepareFullPagedCompaction(writer, candidate).error == FullPagedNativeError.None
    for index in 0..<operations.len: counts[index] = ioCalls(operations[index]) # Actual reached boundaries.
    resetIo()
    assert candidate.close == FileError.None and writer.close == FileError.None
  for channel in 0..<operations.len:
    for skip in 0'u64..<counts[channel]:
      # Each failed artifact has its own process-local forensic namespace and explicit descriptor retirement.
      let directory = path("fault-" & $channel & "-" & $skip)
      var writer = default(FullPagedWriter)
      var candidate = default(FullPagedCandidate)
      var reader = default(FullPagedReader)
      defer:
        resetIo()
        if reader.opened: discard reader.close
        if candidate.opened: discard candidate.close
        if writer.opened: discard writer.close
      writer.seed(directory, source)
      armIo(operations[channel], cint(skip), 1, failedIo)
      let failed = prepareFullPagedCompaction(writer, candidate)
      assert pendingIo() == 0
      resetIo()
      assert failed.error != FullPagedNativeError.None
      if candidate.opened: assert candidate.close == FileError.None
      assert writer.close == FileError.None
      assert openFullPagedReader(reader, directory, source.config).error == FullPagedNativeError.None
      assert uint64(reader.selected.value.epoch) == 1
      assert reader.close == FileError.None
proc main() =
  ## Source-only authority, independent bytes and fixed-policy retirement are checked before publishing this feature.
  let source = historySample(7, 9)
  for cache in 0..1: core(source, cache)
  normal(source)
  maxGeneration(source)
  faultSchedule(source)
  let directory = path("cycles")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  writer.seed(directory, source)
  assert prepareFullPagedCompaction(writer, candidate).error == FullPagedNativeError.None
  assert writer.publish(candidate).error == FullPagedNativeError.None
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    assert prepareFullPagedCompaction(writer, candidate).error == FullPagedNativeError.None
    assert writer.publish(candidate).error == FullPagedNativeError.None
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_compaction", 1000, before, after)
  assert writer.close == FileError.None
  echo "storage full paged compaction PASS"
main()
