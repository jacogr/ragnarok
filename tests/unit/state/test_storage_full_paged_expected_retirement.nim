# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restart-safe expected-manifest retirement requires complete old content and never guesses an epoch from names.
# @@Verification={"arc":"storage_full_paged_expected_retirement_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, full_paged_reference, full_paged_native_fixture]
import ../../../src/storage/[full_paged_codec, full_paged_stream, full_paged_store, paged_io,
  managed_manifest, node_repository, file_errors]
import ../../../src/codec/bounded
proc path(label: string): string =
  ## Every destructive/fault scenario owns a fresh process-private namespace.
  "full-expected-retirement-" & $storageProcessId() & "-" & label
proc read(path: string): string =
  ## Fixture IO is separate from observed native calls and cannot silently substitute missing data.
  try:
    result = readFile(path)
  except:
    assert false, "retirement fixture read failed"
proc write(path, bytes: string) =
  ## Fixture corruption and replacement are explicit test-only mutations of a closed old artifact.
  try:
    writeFile(path, bytes)
  except:
    assert false, "retirement fixture write failed"
proc seed(directory: string, old, target: FullPagedFixture, contextual: bool): FullPagedManifest =
  ## All original owners retire before a new writer uses independently retained old selection authority.
  var config = old.config
  if contextual: config.limits.contextBytes = ByteLimit(4096) # Explicit V2 is never inferred from the artifact.
  var writer = default(FullPagedWriter)
  let context = if contextual: @[4'u8, 7, 1] else: newSeq[byte](0)
  assert initializeFullPagedWriter(writer, directory, config, old.roots, old.records.producer,
    old.header.geometry.entries, old.header.geometry.payloadBytes, context).error ==
        FullPagedNativeError.None
  result = writer.selected.value
  var candidate = default(FullPagedCandidate)
  assert prepareFullPagedReplacement(writer, candidate, target.header.root, target.roots,
    target.records.producer, target.header.geometry.entries, target.header.geometry.payloadBytes,
    context).error == FullPagedNativeError.None
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert writer.close == FileError.None
proc configuration(target: FullPagedFixture, contextual: bool): FullPagedNativeConfig =
  ## Reopen policy is independently selected; full admission never inherits limits from old metadata.
  result = target.config
  if contextual: result.limits.contextBytes = ByteLimit(4096) # Same finite V2 context ceiling as bootstrap.
proc normal(old, target: FullPagedFixture, contextual: bool) =
  ## Current/new/default/wrong-content refusals, foreign pin backpressure and restart idempotence constrain deletion.
  let directory = path("normal-" & $contextual)
  let previous = seed(directory, old, target, contextual)
  let config = target.configuration(contextual)
  var writer = default(FullPagedWriter)
  assert openFullPagedWriter(writer, directory, config).error == FullPagedNativeError.None
  let current = writer.selected.value
  assert writer.reclaimExpectedEpoch(current, current).error ==
      FullPagedNativeError.InvalidCandidate
  assert writer.reclaimExpectedEpoch(default(FullPagedManifest), current).error ==
      FullPagedNativeError.InvalidCandidate
  assert writer.reclaimExpectedEpoch(previous, previous).error == FullPagedNativeError.StaleView
  if not contextual:
    # A legitimate different graph manifest at the same physical epoch cannot authorize this old file.
    let wrong = sample(44).manifest
    assert writer.reclaimExpectedEpoch(wrong, current).error != FullPagedNativeError.None
  var reader = default(FullPagedReader)
  let oldConfig = old.configuration(contextual)
  assert openFullPagedEpochReader(reader, directory, oldConfig, previous).error ==
      FullPagedNativeError.None
  let owned = reader.lookup(old.header.root, key(0)).value.bytes
  let busy = writer.reclaimExpectedEpoch(previous, current)
  assert busy.error == FullPagedNativeError.FileFailure and busy.fileError == FileError.Busy
  assert reader.close == FileError.None
  let removed = writer.reclaimExpectedEpoch(previous, current)
  assert removed.error == FullPagedNativeError.None and not removed.value.alreadyAbsent
  assert removed.value.retirementError == FileError.None
  assert owned[0] == 5
  assert writer.close == FileError.None
  assert openFullPagedWriter(writer, directory, config).error == FullPagedNativeError.None
  let absent = writer.reclaimExpectedEpoch(previous, current)
  assert absent.error == FullPagedNativeError.None and absent.value.alreadyAbsent
  assert openFullPagedEpochReader(reader, directory, oldConfig, previous).error !=
      FullPagedNativeError.None
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  assert reader.lookup(target.header.root, key(0)).value.bytes[0] == 9
  assert reader.close == FileError.None
  assert writer.close == FileError.None
proc faults(old, target: FullPagedFixture) =
  ## Every observed read/scratch/lock/close/unlink/barrier failure preserves CURRENT and resolves by exact reopen/retry.
  let directory = path("count")
  let previous = seed(directory, old, target, true)
  let config = target.configuration(true)
  var writer = default(FullPagedWriter)
  assert openFullPagedWriter(writer, directory, config).error == FullPagedNativeError.None
  let current = writer.selected.value
  resetIo()
  assert writer.reclaimExpectedEpoch(previous, current).error == FullPagedNativeError.None
  let operations = [readIo, writeIo, lockIo, closeIo, truncateIo, unlinkIo, syncIo]
  var counts = default(array[7, uint64])
  for index in 0..<operations.len: counts[index] = uint64(ioCalls(operations[
      index])) # Snapshot before any other observed call.
  resetIo()
  assert writer.close == FileError.None
  for index in 0..<operations.len:
    # Each real cleanup channel is covered once at every observed ordinal, including late close after confirmed unlink.
    assert counts[index] > 0 and counts[index] < 1000
    for skip in 0..<int(counts[index]):
      let attempt = path("fault-" & $index & "-" & $skip)
      let oldManifest = seed(attempt, old, target, true)
      assert openFullPagedWriter(writer, attempt, config).error == FullPagedNativeError.None
      let selected = writer.selected.value
      let bytes = read(attempt & "/CURRENT")
      resetIo()
      armIo(operations[index], cint(skip), 1, failedIo)
      let outcome = writer.reclaimExpectedEpoch(oldManifest, selected)
      assert pendingIo() == 0
      if outcome.error == FullPagedNativeError.None:
        # Only a final descriptor close may fail after an already confirmed unlink/directory barrier.
        assert outcome.value.retirementError != FileError.None
      resetIo()
      assert read(attempt & "/CURRENT") == bytes
      assert writer.close == FileError.None
      assert openFullPagedWriter(writer, attempt, config).error == FullPagedNativeError.None
      assert writer.reclaimExpectedEpoch(oldManifest, selected).error == FullPagedNativeError.None
      assert writer.close == FileError.None
proc renameNative(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Test-only replacement creates a new inode with equal bytes; production never mutates an admitted artifact.
proc identities(old, target: FullPagedFixture) =
  ## Content authority survives restart and equal-byte inode replacement; captured receipts deliberately do not.
  let directory = path("identity")
  let previous = seed(directory, old, target, true)
  var reader = default(FullPagedReader)
  var writer = default(FullPagedWriter)
  assert openFullPagedEpochReader(reader, directory, old.configuration(true), previous).error ==
      FullPagedNativeError.None
  let captured = reader.epochReceipt.value
  assert reader.close == FileError.None
  var destination = directory & "/" & epochName(previous.epoch).value
  var replacement = directory & "/replacement"
  write(replacement, read(destination))
  assert renameNative(replacement.toCString(), destination.toCString()) == 0
  assert openFullPagedWriter(writer, directory, target.configuration(true)).error ==
      FullPagedNativeError.None
  let current = writer.selected.value
  let refused = writer.reclaim(captured, current)
  assert refused.error == FullPagedNativeError.FileFailure and refused.fileError ==
      FileError.RecoveryMismatch
  assert writer.reclaimExpectedEpoch(previous, current).error == FullPagedNativeError.None
  assert writer.close == FileError.None
proc corruption(old, target: FullPagedFixture) =
  ## A correct old header/manifest cannot hide changed payload pages from complete admission before deletion.
  let directory = path("corruption")
  let previous = seed(directory, old, target, true)
  let name = directory & "/" & epochName(previous.epoch).value
  var bytes = read(name)
  bytes[4096] = char(byte(bytes[4096]) xor 1)
  write(name, bytes)
  var writer = default(FullPagedWriter)
  assert openFullPagedWriter(writer, directory, target.configuration(true)).error ==
      FullPagedNativeError.None
  let current = read(directory & "/CURRENT")
  let refused = writer.reclaimExpectedEpoch(previous, writer.selected.value)
  assert refused.error != FullPagedNativeError.None
  assert read(name) == bytes and read(directory & "/CURRENT") == current
  assert writer.close == FileError.None
proc main() =
  ## V1/V2 share guarded retirement; repeated confirmed absence owns no leaked descriptor, graph or scratch allocation.
  let old = sample(5)
  let target = historySample(5, 9)
  normal(old, target, false)
  normal(old, target, true)
  faults(old, target)
  identities(old, target)
  corruption(old, target)
  let directory = path("cycles")
  let previous = seed(directory, old, target, true)
  var writer = default(FullPagedWriter)
  assert openFullPagedWriter(writer, directory, target.configuration(true)).error ==
      FullPagedNativeError.None
  let current = writer.selected.value
  assert writer.reclaimExpectedEpoch(previous, current).error == FullPagedNativeError.None
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Fresh source admission and a real directory barrier qualify every idempotent retry.
    let absent = writer.reclaimExpectedEpoch(previous, current)
    assert absent.error == FullPagedNativeError.None and absent.value.alreadyAbsent
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_expected_retirement", 1000, before, after)
  assert writer.close == FileError.None
  echo "storage full paged expected retirement PASS"
main()
