# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real native full-graph readers validate independent fixture bytes, epoch pins, IO refusal and explicit retirement.
# @@Verification={"arc":"storage_full_paged_readers_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, full_paged_reference]
import ../../../src/storage/[full_paged_codec, full_paged_stream, full_paged_store, paged_io,
  file_errors, managed_manifest, node_records]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc text(bytes: openArray[byte]): string =
  ## Test-only conversion writes complete independent oracle files, not production memory materialization.
  result = newString(bytes.len)
  for index in 0..<bytes.len: result[index] = char(bytes[index]) # Exact fixture bytes.
proc write(path: string, bytes: openArray[byte]) =
  ## Fixture setup is outside observed native operations and never supplies a durability receipt.
  try:
    writeFile(path, text(bytes))
  except:
    assert false, "test fixture write failed"
proc path(label: string): string =
  ## Each suite process owns its native fixture directory under the ignored runner working tree.
  "full-paged-readers-" & $storageProcessId() & "-" & label
proc seed(directory: string, fixture: FullPagedFixture) =
  ## A real stable LOCK and independent full-format bytes allow strict-reader tests before writer implementation.
  var owner = default(PagedDirectory)
  assert openDirectory(owner, directory, true, true) == FileError.None
  assert owner.close == FileError.None
  write(directory & "/" & epochName(ManagedEpoch(1)).value, fixture.io.bytes)
  write(directory & "/CURRENT", fixture.manifest.bytes.value)
func config(fixture: FullPagedFixture): FullPagedNativeConfig =
  ## Expected chain/root originate from the independent test fixture, not disk selection.
  FullPagedNativeConfig(chain: fixture.header.chainId, root: fixture.header.root, limits: policy())
let left = leaf(0, @[1'u8, 2, 3])
let right = leaf(128, newSeq[byte](4097))
let parent = branch(left, right)
let sample = fixture(@[left, right, parent], parent, @[claim(parent, 2, 3, 4100)])
let directory = path("baseline")
seed(directory, sample)

proc main() =
  ## Procedure-scoped cleanup avoids the pinned compiler's unsupported top-level defer lowering.
  block normal:
    # Full native admission preserves owned values, empty/missing semantics and independent reader pins.
    var reader = default(FullPagedReader)
    var second = default(FullPagedReader)
    defer:
      if second.opened: discard second.close
      if reader.opened: discard reader.close
    assert openFullPagedReader(reader, directory, sample.config).error == FullPagedNativeError.None
    var moved = move(reader)
    assert not reader.opened and moved.opened
    reader = move(moved)
    assert openFullPagedReader(second, directory, sample.config).error == FullPagedNativeError.None
    let owned = reader.lookup(sample.header.root, key(0))
    assert owned.error == FullPagedNativeError.None and owned.value.bytes == @[1'u8, 2, 3]
    assert reader.lookup(sample.header.root, key(64)).error == FullPagedNativeError.None
    assert not reader.lookup(sample.header.root, key(64)).value.present
    assert reader.lookup(sample.header.root, key(128)).value.bytes.len == 4097
    var writer = default(PagedDirectory)
    var exclusive = default(PagedFile)
    assert openDirectory(writer, directory, false, true) == FileError.None
    assert openEpoch(exclusive, writer, ManagedEpoch(1), PagedPin.Exclusive,
      policy().dataset.bytes) == FileError.Busy
    assert reader.close == FileError.None
    assert second.lookup(sample.header.root, key(0)).value.bytes == @[1'u8, 2, 3]
    assert second.close == FileError.None
    assert openEpoch(exclusive, writer, ManagedEpoch(1), PagedPin.Exclusive,
      policy().dataset.bytes) == FileError.None
    assert exclusive.close == FileError.None and writer.close == FileError.None
    assert owned.value.bytes == @[1'u8, 2, 3]
    assert reader.close == FileError.Uninitialized

  block identities:
    # Wrong expected roots/chains and a light-width CURRENT refuse before any reader is adopted.
    var reader = default(FullPagedReader)
    var wrong = sample.config
    wrong.root = default(StateRoot)
    let refused = openFullPagedReader(reader, directory, wrong)
    assert refused.error == FullPagedNativeError.CodecFailure
    assert refused.codecError == FullPagedError.WrongRoot and not reader.opened
    let width = path("width")
    seed(width, sample)
    var bytes = sample.manifest.bytes.value
    var extra = text(bytes)
    extra.add(char(0))
    try:
      writeFile(width & "/CURRENT", extra)
    except:
      assert false, "wrong-mode fixture write failed"
    let mode = openFullPagedReader(reader, width, sample.config)
    assert mode.error == FullPagedNativeError.FileFailure and not reader.opened
    assert mode.fileError == FileError.UnsupportedLayout

  block invalidGraph:
    # A fully checksummed artifact with valid individual records still cannot become a native complete reader.
    let reversed = branch(right, left)
    let bad = fixture(@[left, right, reversed], reversed, @[claim(reversed, 2, 3, 4100)])
    let target = path("graph")
    seed(target, bad)
    var reader = default(FullPagedReader)
    let refused = openFullPagedReader(reader, target, bad.config)
    assert refused.error == FullPagedNativeError.GraphFailure and not reader.opened
    assert refused.graphError == FullPagedStreamError.InvalidGraph

  block faults:
    # Every observed native read/write/flock/truncate/close refusal yields no reader or partial graph authority.
    var control = default(FullPagedReader)
    resetIo()
    assert openFullPagedReader(control, directory, sample.config).error == FullPagedNativeError.None
    var counts = default(array[5, uint64])
    let operations = [readIo, writeIo, lockIo, truncateIo, closeIo]
    for index in 0..<operations.len: counts[index] = ioCalls(operations[index]) # Capture actual syscall counts.
    resetIo()
    assert control.close == FileError.None
    for channel in 0..<operations.len:
      # Faults are armed only after stable independent setup; even cleanup-close refusal cannot grant success.
      for skip in 0'u64..<counts[channel]:
        var reader = default(FullPagedReader)
        armIo(operations[channel], cint(skip), 1, failedIo)
        let refused = openFullPagedReader(reader, directory, sample.config)
        assert pendingIo() == 0
        resetIo()
        assert refused.error != FullPagedNativeError.None and not reader.opened
    for operation in [readIo, writeIo, lockIo, truncateIo]:
      # EINTR repeats only idempotent operations on the same still-owned descriptor/extent.
      var reader = default(FullPagedReader)
      armIo(operation, 0, 1, interruptedIo)
      assert openFullPagedReader(reader, directory, sample.config).error ==
          FullPagedNativeError.None
      assert pendingIo() == 0
      resetIo()
      assert reader.close == FileError.None

  block retirement:
    # Fresh native scratch and retained epoch resources retire fully after repeated complete admission.
    let before = getOccupiedMem()
    for iteration in 0..<1000:
      var reader = default(FullPagedReader)
      assert openFullPagedReader(reader, directory, sample.config).error ==
          FullPagedNativeError.None
      assert reader.lookup(sample.header.root, key(0)).value.bytes.len == 3
      assert reader.close == FileError.None
    let after = getOccupiedMem()
    assert before == after
    recordArcRelease("storage_full_paged_readers", 1000, before, after)
  echo "storage full paged readers PASS"
main()
