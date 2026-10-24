# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently known old manifests recover pinned full readers and fresh exact cleanup receipts after owner retirement.
# @@Verification={"arc":"storage_full_paged_epoch_reopen_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, full_paged_reference, full_paged_native_fixture]
import ../../../src/storage/[full_paged_codec, full_paged_stream, full_paged_store, paged_io,
  managed_manifest, file_errors]
proc path(label: string): string =
  ## New namespaces isolate genuine pins and fault schedules without namespace-wide recovery scans.
  "full-epoch-reopen-" & $storageProcessId() & "-" & label
proc seed(directory: string, old, target: FullPagedFixture): FullPagedManifest =
  ## Retire all original owners; only the independent passive manifest survives the simulated restart boundary.
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  writer.seed(directory, old)
  result = writer.selected.value
  writer.prepare(candidate, target)
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert writer.close == FileError.None
proc normal(old, target: FullPagedFixture) =
  ## Fresh exact epoch readers remain independent of CURRENT and exclude physical reclamation until explicit retirement.
  let directory = path("normal")
  let expected = seed(directory, old, target)
  var reader = default(FullPagedReader)
  var writer = default(FullPagedWriter)
  assert openFullPagedEpochReader(reader, directory, old.config, expected).error ==
      FullPagedNativeError.None
  assert reader.selected.value.bytes.value == expected.bytes.value
  let owned = reader.lookup(old.header.root, key(0)).value.bytes
  assert owned[0] == 5
  let receipt = reader.epochReceipt.value
  assert openFullPagedWriter(writer, directory, target.config).error == FullPagedNativeError.None
  let current = writer.selected.value
  let busy = writer.reclaim(receipt, current)
  assert busy.error == FullPagedNativeError.FileFailure and busy.fileError == FileError.Busy
  assert reader.close == FileError.None
  assert owned[0] == 5
  assert writer.reclaim(receipt, current).error == FullPagedNativeError.None
  assert writer.close == FileError.None
  assert openFullPagedEpochReader(reader, directory, old.config, expected).error !=
      FullPagedNativeError.None
  assert not reader.opened
  assert openFullPagedReader(reader, directory, target.config).error == FullPagedNativeError.None
  assert reader.lookup(old.header.root, key(0)).value.bytes[0] == 5
  assert reader.close == FileError.None
proc faults(old, target: FullPagedFixture) =
  ## Every observed native admission/retirement refusal exposes no reader and leaves both immutable epochs readable.
  let directory = path("faults")
  let expected = seed(directory, old, target)
  var reader = default(FullPagedReader)
  resetIo()
  assert openFullPagedEpochReader(reader, directory, old.config, expected).error ==
      FullPagedNativeError.None
  let counts = [ioCalls(readIo), ioCalls(writeIo), ioCalls(lockIo), ioCalls(closeIo), ioCalls(truncateIo)]
  assert reader.close == FileError.None
  let operations = [readIo, writeIo, lockIo, closeIo, truncateIo]
  for index in 0..<operations.len:
    # Graph scratch writes and truncation are genuine old-epoch admission work, not fixture IO.
    assert counts[index] > 0 and counts[index] < 1000
    for skip in 0..<int(counts[index]):
      resetIo()
      armIo(operations[index], cint(skip), 1, failedIo)
      let opened = openFullPagedEpochReader(reader, directory, old.config, expected)
      assert opened.error != FullPagedNativeError.None and not reader.opened and pendingIo() == 0
      resetIo()
      assert openFullPagedEpochReader(reader, directory, old.config, expected).error ==
          FullPagedNativeError.None
      assert reader.close == FileError.None
  assert openFullPagedEpochReader(reader, directory, target.config, expected).error !=
      FullPagedNativeError.None
  assert not reader.opened
  assert openFullPagedEpochReader(reader, directory, old.config, default(
      FullPagedManifest)).error != FullPagedNativeError.None
  assert not reader.opened
proc main() =
  ## Fresh passive manifests recover old authority without trusting any new root or retaining original writer state.
  let old = sample(5)
  let target = historySample(5, 9)
  normal(old, target)
  faults(old, target)
  let directory = path("cycles")
  let expected = seed(directory, old, target)
  var reader = default(FullPagedReader)
  assert openFullPagedEpochReader(reader, directory, old.config, expected).error ==
      FullPagedNativeError.None
  assert reader.close == FileError.None
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Each explicit immutable reopen owns and retires an independent parent descriptor and shared epoch pin.
    assert openFullPagedEpochReader(reader, directory, old.config, expected).error ==
        FullPagedNativeError.None
    assert reader.close == FileError.None
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_epoch_reopen", 1000, before, after)
  echo "storage full paged epoch reopen PASS"
main()
