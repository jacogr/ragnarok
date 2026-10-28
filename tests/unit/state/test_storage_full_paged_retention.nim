# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained complete-root unions remain queryable after exact captured physical epoch reclamation.
# @@Verification={"arc":"storage_full_paged_retention_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../support/state_full_paged_reference
import ../../support/state_full_paged_native_fixture
import ../../../src/storage/full_paged_codec as storage_full_paged_codec
import ../../../src/storage/full_paged_stream as storage_full_paged_stream
import ../../../src/storage/full_paged_store as storage_full_paged_store
import ../../../src/storage/paged_io as storage_paged_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/storage/durability as storage_durability
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc path(label: string): string =
  ## Every suite namespace is isolated beneath the ignored native runner working directory.
  "full-paged-retention-" & $storageProcessId() & "-" & label
proc normal(old, union, fresh: FullPagedFixture) =
  ## Logical root retention is independent of physical epoch retention, reader pins and exact directory-sync receipts.
  let directory = path("normal")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  var first = default(FullPagedReader)
  var both = default(FullPagedReader)
  var newest = default(FullPagedReader)
  defer:
    resetIo()
    if newest.opened: discard newest.close
    if both.opened: discard both.close
    if first.opened: discard first.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  writer.seed(directory, old)
  assert openFullPagedReader(first, directory, old.config).error == FullPagedNativeError.None
  let one = first.epochReceipt.value
  let prior = writer.selected.value
  writer.prepare(candidate, union)
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert openFullPagedReader(both, directory, union.config).error == FullPagedNativeError.None
  assert both.lookup(old.header.root, key(0)).value.bytes == @[7'u8]
  assert both.lookup(fresh.header.root, key(0)).value.bytes == @[9'u8]
  let busy = writer.reclaim(one, writer.selected.value)
  assert busy.error == FullPagedNativeError.FileFailure and busy.fileError == FileError.Busy
  assert writer.reclaim(one, prior).error == FullPagedNativeError.StaleView
  assert writer.reclaim(default(FullPagedEpochReceipt), writer.selected.value).error ==
      FullPagedNativeError.InvalidCandidate
  assert first.close == FileError.None
  let removed = writer.reclaim(one, writer.selected.value)
  assert removed.error == FullPagedNativeError.None and not removed.value.alreadyAbsent
  assert removed.value.durability == StorageDurability.FileAndDirectorySynced
  assert removed.value.retirementError == FileError.None
  assert writer.reclaim(one, writer.selected.value).value.alreadyAbsent
  assert both.lookup(old.header.root, key(0)).value.bytes == @[7'u8]
  let two = both.epochReceipt.value
  writer.prepare(candidate, fresh)
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert openFullPagedReader(newest, directory, fresh.config).error == FullPagedNativeError.None
  assert newest.lookup(old.header.root, key(0)).error == FullPagedNativeError.GraphFailure
  assert newest.lookup(old.header.root, key(0)).graphError == FullPagedStreamError.UnknownRoot
  assert both.lookup(old.header.root, key(0)).value.bytes == @[7'u8]
  assert both.close == FileError.None
  assert writer.reclaim(two, writer.selected.value).error == FullPagedNativeError.None
  assert newest.lookup(fresh.header.root, key(0)).value.bytes == @[9'u8]
proc maxRoots() =
  ## The fixed header's exact64-root inventory is a supported complete history, while a narrower caller policy refuses it.
  var records: seq[TrieRecord] = @[]
  var claims: seq[FullPagedRoot] = @[]
  for index in 0..<FullPagedMaxRoots:
    # Independent one-leaf complete revisions differ only in their retained value, never sharing one root identity.
    let record = leaf(0, @[byte(index)])
    records.add(record)
    claims.add(claim(record, 1, 1, 1))
  let full = fixture(records, records[records.len-1], claims)
  let directory = path("max-roots")
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  defer:
    if reader.opened: discard reader.close
    if writer.opened: discard writer.close
  writer.seed(directory, full)
  assert openFullPagedReader(reader, directory, full.config).error == FullPagedNativeError.None
  for index in 0..<records.len:
    assert reader.lookup(claims[index].root, key(0)).value.bytes == @[byte(index)]
  assert reader.close == FileError.None and writer.close == FileError.None
  var narrow = full.config
  narrow.limits.roots = ElementLimit(63)
  let refused = openFullPagedReader(reader, directory, narrow)
  assert refused.error == FullPagedNativeError.GraphFailure and not reader.opened
  assert refused.graphError == FullPagedStreamError.LimitExceeded
proc prepared(writer: var FullPagedWriter, directory: string,
    old: FullPagedFixture): FullPagedEpochReceipt =
  ## Capture epoch one under SH, advance independently to epoch two, then release old readers before cleanup tests.
  writer.seed(directory, old)
  var reader = default(FullPagedReader)
  var candidate = default(FullPagedCandidate)
  assert openFullPagedReader(reader, directory, old.config).error == FullPagedNativeError.None
  let receipt = reader.epochReceipt.value
  writer.prepare(candidate, old)
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert reader.close == FileError.None
  receipt
proc faultSchedule(old: FullPagedFixture) =
  ## Every observed reclamation read/write/flock/truncate/unlink/sync/close boundary preserves exact source/old-inode safety.
  let operations = [readIo, writeIo, lockIo, truncateIo, unlinkIo, syncIo, closeIo]
  var counts = default(array[7, uint64])
  block baseline:
    # Count actual cleanup operations after all independent authoring and old receipt capture.
    var writer = default(FullPagedWriter)
    let receipt = prepared(writer, path("fault-control"), old)
    let expected = writer.selected.value
    resetIo()
    assert writer.reclaim(receipt, expected).error == FullPagedNativeError.None
    for index in 0..<operations.len: counts[index] = ioCalls(operations[index]) # Actual reached boundaries.
    resetIo()
    assert writer.close == FileError.None
  for operation in 0..<operations.len:
    for skip in 0'u64..<counts[operation]:
      # Exact fresh namespaces ensure an earlier interrupted unlink cannot hide the next selected fault.
      let directory = path("fault-" & $operation & "-" & $skip)
      var writer = default(FullPagedWriter)
      defer:
        resetIo()
        if writer.opened: discard writer.close
      let receipt = prepared(writer, directory, old)
      let expected = writer.selected.value
      armIo(operations[operation], cint(skip), 1, failedIo)
      let removed = writer.reclaim(receipt, expected)
      assert pendingIo() == 0, "unconsumed reclaim fault channel=" & $operation & " skip=" & $skip
      resetIo()
      if removed.error == FullPagedNativeError.None:
        # Only post-confirmation old-file retirement errors can accompany successful removal.
        assert removed.value.retirementError != FileError.None
      assert writer.close == FileError.None
      assert openFullPagedWriter(writer, directory, old.config).error == FullPagedNativeError.None
      let retry = writer.reclaim(receipt, writer.selected.value)
      assert retry.error == FullPagedNativeError.None
      assert writer.reclaim(receipt, writer.selected.value).value.alreadyAbsent
      assert writer.close == FileError.None
proc policyBinding(old: FullPagedFixture) =
  ## Every independent policy scalar binds the captured old-epoch receipt, including harmless increases in allowance.
  let directory = path("policy")
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  var candidate = default(FullPagedCandidate)
  var receipts = newSeq[FullPagedEpochReceipt](15)
  defer:
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  writer.seed(directory, old)
  for channel in 0..<15:
    # Each altered policy still admits the complete fixture; only exact receipt-policy binding must refuse later cleanup.
    var changed = old.config
    case channel
    of 0: changed.limits.dataset.entries = ElementLimit(1001)
    of 1: changed.limits.dataset.bytes = ByteLimit(1000001)
    of 2: changed.limits.trie.items = ElementLimit(1001)
    of 3: changed.limits.trie.nodes = TrieNodeLimit(1001)
    of 4: changed.limits.trie.perValue = ByteLimit(10001)
    of 5: changed.limits.trie.totalValueBytes = ByteLimit(100001)
    of 6: changed.limits.roots = ElementLimit(63)
    of 7: changed.limits.cachePages = ElementLimit(0)
    of 8: changed.limits.workingBytes = ByteLimit(5000001)
    of 9: changed.limits.scratchBytes = ByteLimit(2001)
    of 10: changed.limits.work.ioCalls = ElementLimit(1000001)
    of 11: changed.limits.work.hashes = ElementLimit(1000001)
    of 12: changed.limits.work.visits = ElementLimit(10001)
    of 13: changed.limits.work.readBytes = ByteLimit(100000001)
    else: changed.limits.work.writeBytes = ByteLimit(1000001)
    assert openFullPagedReader(reader, directory, changed).error == FullPagedNativeError.None
    receipts[channel] = reader.epochReceipt.value
    assert reader.close == FileError.None
  writer.prepare(candidate, old)
  assert writer.publish(candidate).error == FullPagedNativeError.None
  for receipt in receipts:
    assert writer.reclaim(receipt, writer.selected.value).error ==
        FullPagedNativeError.InvalidCandidate
proc renameNative(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Test-only namespace substitution uses the real SDK to replace an old path with an independently created inode.
proc identities(old: FullPagedFixture) =
  ## Equal bytes and equal roots cannot authorize cleanup of a different inode or another database namespace.
  var writer = default(FullPagedWriter)
  var other = default(FullPagedWriter)
  defer:
    if other.opened: discard other.close
    if writer.opened: discard writer.close
  let directory = path("identity")
  let receipt = prepared(writer, directory, old)
  let name = epochName(ManagedEpoch(1)).value
  var source = directory & "/replacement"
  var target = directory & "/" & name
  var bytes = newString(old.io.bytes.len)
  for index in 0..<bytes.len: bytes[index] = char(old.io.bytes[index]) # Same artifact, new physical inode.
  try:
    writeFile(source, bytes)
  except:
    assert false, "inode substitution fixture write failed"
  assert renameNative(source.toCString(), target.toCString()) == 0
  let refused = writer.reclaim(receipt, writer.selected.value)
  assert refused.error == FullPagedNativeError.FileFailure
  assert refused.fileError == FileError.RecoveryMismatch
  let second = path("namespace")
  let legitimate = prepared(other, second, old)
  assert other.reclaim(receipt, other.selected.value).error == FullPagedNativeError.InvalidCandidate
  assert other.reclaim(legitimate, other.selected.value).error == FullPagedNativeError.None
proc main() =
  ## Native lifetime and exact-policy checks complement the shared publication/pin interleaving model.
  let old = sample(7)
  let fresh = sample(9)
  normal(old, historySample(7, 9), fresh)
  maxRoots()
  policyBinding(old)
  identities(old)
  faultSchedule(old)
  let directory = path("cycles")
  var writer = default(FullPagedWriter)
  let receipt = prepared(writer, directory, old)
  assert writer.reclaim(receipt, writer.selected.value).error == FullPagedNativeError.None
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    assert writer.reclaim(receipt, writer.selected.value).value.alreadyAbsent
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_retention", 1000, before, after)
  assert writer.close == FileError.None
  echo "storage full paged retention PASS"
main()
