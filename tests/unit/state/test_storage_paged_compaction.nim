# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-derived compaction preserves retained knowledge/sequence through native faults and independent byte witnesses.
# @@Verification={"arc":"storage_paged_compaction_arc_release"}
import std/[assertions, syncio]
import ../../support/[paged_native_fixture, paged_reference, storage_io, arc_evidence]
import ../../../src/storage/paged/[store as paged_store, codec as paged_codec,
    stream as paged_stream]
import ../../../src/storage/file/errors as file_errors
import ../../../src/storage/paged/io as paged_io
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/light/[delta as light_delta, state_cache as light_state_cache]
import ../../../src/storage/state_proof
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Provider refusal must remain independent of local IO errors.
proc text(bytes: seq[byte]): string =
  ## Detached independent oracle bytes are compared against exact on-disk artifacts.
  result = newString(bytes.len)
  for index in 0..<bytes.len: result[index] = char(bytes[index])
proc captured(path: string): string =
  ## Fixture transport failures must stop the native suite.
  try:
    return readFile(path)
  except:
    assert false, "read compaction witness"
proc path(label: string): string =
  ## Unique process/trial namespaces avoid destructive fixture reset.
  "paged-compaction-" & $storageProcessId() & "-" & label
proc seed(writer: var PagedWriter, directory: string, fixture: PagedNativeFixture) =
  ## A separately synchronized source starts each independent compaction trial.
  assert initializePagedWriter(writer, directory, fixture.config, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
proc normal(fixture: PagedNativeFixture) =
  ## An equal JAM root with fewer retained queries stays that exact knowledge set after compaction.
  let directory = path("normal")
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  var retained = default(PagedReader)
  var reader = default(PagedReader)
  defer:
    if reader.opened: discard reader.close
    if retained.opened: discard retained.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  let records = @[fixture.records[0], fixture.records[1]]
  let payload = fixture.payload-41-uint64(fixture.records[2].proof.nodes.len)*64
  assert preparePagedReplacement(writer, candidate, records.nativeProducer,
    uint64(records.len), payload).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert openPagedReader(retained, directory, fixture.config).error == PagedNativeError.None
  assert preparePagedCompaction(writer, candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.epoch) == 2
  assert uint64(writer.selected.value.sequence) == 1
  assert writer.publish(candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.epoch) == 3
  assert uint64(writer.selected.value.sequence) == 1
  assert uint64(retained.selected.value.epoch) == 2
  var reference = pagedReference(fixture.config.chain, fixture.config.root, records)
  reference.bytes.put(88, 3)
  reference.bytes.put(96, 1)
  reference.recommit()
  assert captured(directory & "/CURRENT") == text(reference.manifest)
  assert captured(directory & "/" & epochName(ManagedEpoch(3)).value) == text(reference.bytes)
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  assert reader.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 7
  assert reader.lookup(pagedKey(128), pagedPolicy().work).value.bytes.len == 0
  assert reader.lookup(pagedKey(255), pagedPolicy().work).error == PagedNativeError.UnknownKey
  assert retained.lookup(pagedKey(255), pagedPolicy().work).error == PagedNativeError.UnknownKey
  assert writer.close == FileError.None
  assert reader.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 7
  assert reader.close == FileError.None and retained.close == FileError.None
proc maxSequence(fixture: PagedNativeFixture) =
  ## Ordinary-sequence exhaustion blocks replacement while compaction still preserves that exact maximum.
  let directory = path("max-sequence")
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  defer:
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  assert writer.close == FileError.None
  var reference = pagedReference(fixture.config.chain, fixture.config.root, fixture.records)
  reference.bytes.put(96, high(uint64))
  reference.recommit()
  try:
    # Independently rehashed source counters cannot rely on a forged in-memory result.
    writeFile(directory & "/CURRENT", text(reference.manifest))
    writeFile(directory & "/" & epochName(ManagedEpoch(1)).value, text(reference.bytes))
  except:
    assert false, "max-sequence fixture write"
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.CounterExhausted
  assert preparePagedCompaction(writer, candidate).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.sequence) == high(uint64)
  assert uint64(writer.selected.value.epoch) == 2
  assert writer.close == FileError.None
proc trial(fixture: PagedNativeFixture, operation: cint, skip: int): array[4, uint64] =
  ## Each observed authoring read/write/barrier/pin fault must fire and cannot change CURRENT.
  result = default(array[4, uint64])
  let directory = path("fault-" & $operation & "-" & $skip)
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  defer:
    resetIo()
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  let before = captured(directory & "/CURRENT")
  resetIo()
  if operation != 0: armIo(operation, cint(skip), 1, failedIo)
  let prepared = preparePagedCompaction(writer, candidate)
  if operation == 0:
    # Baseline counts come from a real successfully sealed native target.
    assert prepared.error == PagedNativeError.None
    result = [ioCalls(readIo), ioCalls(writeIo), ioCalls(syncIo), ioCalls(lockIo)]
  else:
    # No failed preparation may publish a partial or fallback artifact.
    assert pendingIo() == 0 and prepared.error != PagedNativeError.None
  resetIo()
  assert captured(directory & "/CURRENT") == before
  if prepared.error != PagedNativeError.None and candidate.opened:
    assert writer.publish(candidate).error == PagedNativeError.InvalidCandidate
  if candidate.opened: assert candidate.close == FileError.None
  assert writer.close == FileError.None
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  assert uint64(writer.selected.value.epoch) == 1 and uint64(writer.selected.value.sequence) == 0
  assert writer.close == FileError.None
proc faultSchedule(fixture: PagedNativeFixture) =
  ## Bounded actual-call schedules include the source revalidation and complete target verification.
  let counts = trial(fixture, 0, 0)
  let operations = [readIo, writeIo, syncIo, lockIo]
  for index in 0..<operations.len:
    assert counts[index] > 0 and counts[index] < 1000
    for skip in 0..<int(counts[index]): discard trial(fixture, operations[index], skip)
proc cycle(directory: string, fixture: PagedNativeFixture) =
  ## Native writer/candidate resources and all copied pages retire before allocation sampling.
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  assert preparePagedCompaction(writer, candidate).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert candidate.close == FileError.Uninitialized
  assert writer.close == FileError.None
proc main() =
  ## Checked native execution anchors knowledge preservation with independently recomputed artifacts.
  let fixture = nativeFixture(7)
  normal(fixture)
  maxSequence(fixture)
  faultSchedule(fixture)
  let directory = path("cycles")
  var writer = default(PagedWriter)
  seed(writer, directory, fixture)
  assert writer.close == FileError.None
  cycle(directory, fixture)
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(directory, fixture)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_compaction", 1000, before, after)
  echo "PASS paged compaction: exact retained knowledge, unchanged sequence, bounded authenticated copy and native fault atomicity"
main()
