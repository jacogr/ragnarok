# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real directory/file/pin owners qualify durable selection, retained readers and guarded epoch reclamation.
# @@Verification={"arc":"storage_paged_native_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../support/storage_crash
import ../../support/storage_paged_native_fixture
import ../../support/storage_paged_reference
import ../../../src/storage/paged_store as storage_paged_store
import ../../../src/storage/paged_io as storage_paged_io
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/paged_stream as storage_paged_stream
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/durability as storage_durability
import ../../../src/storage/state_proof as storage_state_proof
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Provider refusal is independent of native IO instrumentation.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Counter exhaustion refuses before dispatching the observed hash provider.
proc path(label: string): string =
  ## Each suite process owns an isolated ignored native working directory.
  "paged-native-" & $storageProcessId() & "-" & label
proc normal(old, fresh: PagedNativeFixture) =
  ## Independent reader descriptors/pins survive writer close, same-root replacement and explicit root advancement.
  let directory = path("normal")
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  var reader = default(PagedReader)
  var newest = default(PagedReader)
  defer:
    resetIo()
    resetHash(0)
    if newest.opened: discard newest.close
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  let initialized = initializePagedWriter(writer, directory, old.config, old.records.nativeProducer,
    uint64(old.records.len), old.payload)
  var transferredWriter = move(writer)
  assert not writer.opened and transferredWriter.opened
  writer = move(transferredWriter)
  assert not transferredWriter.opened
  assert initialized.error == PagedNativeError.None
  assert initialized.value.retirementError == FileError.None and initialized.value.writerUsable
  assert initialized.value.durability == StorageDurability.FileAndDirectorySynced
  assert uint64(writer.selected.value.epoch) == 1 and uint64(writer.selected.value.sequence) == 0
  assert openPagedReader(reader, directory, old.config).error == PagedNativeError.None
  let receipt = reader.epochReceipt.value
  let owned = reader.lookup(pagedKey(0), pagedPolicy().work).value
  assert owned.bytes[0] == 7
  assert reader.lookup(pagedKey(128), pagedPolicy().work).value.bytes.len == 0
  assert reader.lookup(pagedKey(255), pagedPolicy().work).value.kind == StateLookupKind.Absent
  assert reader.lookup(pagedKey(64), pagedPolicy().work).error == PagedNativeError.UnknownKey
  assert preparePagedReplacement(writer, candidate, old.records.nativeProducer,
    uint64(old.records.len), old.payload).error == PagedNativeError.None
  var transferred = move(candidate)
  assert not candidate.opened and transferred.opened
  candidate = move(transferred)
  assert not transferred.opened
  let published = writer.publish(candidate)
  assert published.error == PagedNativeError.None and published.value.writerUsable
  assert not candidate.opened
  assert uint64(writer.selected.value.epoch) == 2 and uint64(writer.selected.value.sequence) == 1
  let busy = writer.reclaim(receipt, writer.selected.value)
  assert busy.error == PagedNativeError.FileFailure and busy.fileError == FileError.Busy
  assert reader.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 7
  assert uint64(reader.selected.value.epoch) == 1
  assert reader.close == FileError.None
  let removed = writer.reclaim(receipt, writer.selected.value)
  assert removed.error == PagedNativeError.None and not removed.value.alreadyAbsent
  assert removed.value.retirementError == FileError.None
  assert writer.reclaim(receipt, writer.selected.value).value.alreadyAbsent
  assert preparePagedAdvance(writer, candidate, fresh.config.root, fresh.records.nativeProducer,
    uint64(fresh.records.len), fresh.payload).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.epoch) == 3 and uint64(writer.selected.value.sequence) == 1
  assert openPagedReader(newest, directory, fresh.config).error == PagedNativeError.None
  assert writer.close == FileError.None
  assert newest.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 9
  assert owned.bytes[0] == 7
  assert newest.close == FileError.None
  assert openPagedReader(reader, directory, old.config).error == PagedNativeError.FileFailure
  assert not reader.opened
  assert openPagedWriter(writer, directory, fresh.config).error == PagedNativeError.None
  assert writer.close == FileError.None
proc seeded(writer: var PagedWriter, label: string, fixture: PagedNativeFixture): string =
  ## Every fault trial starts from a separately created, synchronized namespace.
  result = path(label)
  assert initializePagedWriter(writer, result, fixture.config, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
proc prepare(writer: var PagedWriter, candidate: var PagedCandidate, fixture: PagedNativeFixture) =
  ## Exercise the real append/fsync path before isolating publication faults.
  assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
proc policies(fixture: PagedNativeFixture) =
  ## Pure quota/provider refusal preserves reader authority; independent writer opens remain exclusive.
  var writer = default(PagedWriter)
  var second = default(PagedWriter)
  var reader = default(PagedReader)
  let directory = seeded(writer, "policies", fixture)
  defer:
    resetHash(0)
    resetIo()
    if reader.opened: discard reader.close
    if second.opened: discard second.close
    if writer.opened: discard writer.close
  let busy = openPagedWriter(second, directory, fixture.config)
  assert busy.error == PagedNativeError.FileFailure and busy.fileError == FileError.Busy
  assert not second.opened
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  let selected = reader.selected.value
  let protected = writer.reclaim(reader.epochReceipt.value, selected)
  assert protected.error == PagedNativeError.InvalidCandidate
  let quota = reader.lookup(pagedKey(0), default(PagedWorkLimits))
  assert quota.error == PagedNativeError.StreamFailure and quota.streamError ==
      PagedStreamError.LimitExceeded
  resetHash(1)
  let provider = reader.lookup(pagedKey(0), pagedPolicy().work)
  resetHash(0)
  assert provider.error == PagedNativeError.StreamFailure and provider.streamError ==
      PagedStreamError.BackendFailure
  assert reader.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 7
  armIo(readIo, 0, 1, failedIo)
  let uncertain = reader.lookup(pagedKey(0), pagedPolicy().work)
  assert uncertain.error == PagedNativeError.StreamFailure and pendingIo() == 0
  resetIo()
  assert reader.lookup(pagedKey(0), pagedPolicy().work).error == PagedNativeError.RecoveryRequired
  assert reader.close == FileError.None
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  assert reader.close == FileError.None
  assert writer.close == FileError.None
proc staleCandidate(fixture: PagedNativeFixture) =
  ## Closing/reopening an equal head creates a new writer incarnation; forensic epochs are never overwritten.
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  let directory = seeded(writer, "stale", fixture)
  defer:
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  prepare(writer, candidate, fixture)
  assert writer.close == FileError.None
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.StaleView
  assert candidate.close == FileError.None
  let collision = preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload)
  assert collision.error == PagedNativeError.FileFailure and collision.fileError ==
      FileError.AlreadyExists
  assert not candidate.opened
  assert uint64(writer.selected.value.epoch) == 1
  assert writer.close == FileError.None
proc publicationFault(fixture: PagedNativeFixture, operation: cint, skip: int) =
  ## Inject one observed native boundary; strict reopen alone decides the actual old/new synchronized manifest.
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  let directory = seeded(writer, "publish-fault-" & $operation & "-" & $skip, fixture)
  defer:
    resetIo()
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  prepare(writer, candidate, fixture)
  resetIo()
  armIo(operation, cint(skip), 1, failedIo)
  let publication = writer.publish(candidate)
  assert pendingIo() == 0
  resetIo()
  if publication.error == PagedNativeError.None:
    # Only post-confirmation retirement/adoption faults retain a successful durable selection.
    assert publication.value.retirementError != FileError.None
    assert not publication.value.writerUsable
    assert uint64(publication.value.manifest.sequence) == 1
    assert writer.selected.error == PagedNativeError.RecoveryRequired
  else:
    # Before confirmation there is no usable receipt, and no successful-prefix fallback is extracted.
    assert publication.error in {PagedNativeError.FileFailure, PagedNativeError.StreamFailure}
  if candidate.opened: assert candidate.close == FileError.None
  assert writer.close == FileError.None
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  let sequence = uint64(writer.selected.value.sequence)
  assert sequence == 0 or sequence == 1
  if publication.error == PagedNativeError.None: assert sequence == 1
  assert writer.close == FileError.None
proc publicationFaults(fixture: PagedNativeFixture) =
  ## Measure the normal path once, then require every injected read/write/barrier/rename/retirement/pin to fire.
  let operations = [readIo, writeIo, syncIo, renameIo, closeIo, lockIo]
  var counts = default(array[6, uint64])
  block:
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    discard seeded(writer, "publish-counts", fixture)
    prepare(writer, candidate, fixture)
    resetIo()
    assert writer.publish(candidate).error == PagedNativeError.None
    for index in 0..<operations.len: counts[index] = ioCalls(operations[index])
    resetIo()
    assert writer.close == FileError.None
  for index in 0..<operations.len:
    assert counts[index] > 0 and counts[index] < 1000
    for skip in 0..<int(counts[index]): publicationFault(fixture, operations[index], skip)
proc shortAndInterrupted(fixture: PagedNativeFixture) =
  ## Positive short reads/writes and EINTR retry the same unfinished syscall, while close is never retried.
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  var candidate = default(PagedCandidate)
  let directory = seeded(writer, "short", fixture)
  defer:
    resetIo()
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  limitWrites(13)
  limitReads(17)
  armIo(writeIo, 0, 2, interruptedIo)
  prepare(writer, candidate, fixture)
  assert pendingIo() == 0
  armIo(syncIo, 0, 2, interruptedIo)
  assert writer.publish(candidate).error == PagedNativeError.None
  assert pendingIo() == 0
  armIo(lockIo, 0, 2, interruptedIo)
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  assert pendingIo() == 0
  armIo(readIo, 0, 2, interruptedIo)
  assert reader.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 7
  assert pendingIo() == 0
  resetIo()
  reuseClosedDescriptor()
  armIo(closeIo, 0, 1, interruptedIo)
  let retired = reader.close
  assert retired == FileError.IoFailure
  assert reusedDescriptorOpen() == 1
  assert not reader.opened and reader.close == FileError.Uninitialized
  resetIo()
  assert writer.close == FileError.None
proc authoringFailure(fixture: PagedNativeFixture) =
  ## Zero-progress authoring preserves an explicit-close forensic candidate and leaves the source usable.
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  discard seeded(writer, "zero", fixture)
  defer:
    resetIo()
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  assert zeroWrites(0, 1) == 0
  let refused = preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload)
  assert refused.error == PagedNativeError.StreamFailure and refused.streamError ==
      PagedStreamError.IOFailure
  assert pendingZeroWrites() == 0 and candidate.opened
  resetIo()
  assert writer.publish(candidate).error == PagedNativeError.InvalidCandidate
  assert uint64(writer.selected.value.sequence) == 0
  assert candidate.close == FileError.None
  assert writer.close == FileError.None
proc readerCycle(directory: string, fixture: PagedNativeFixture) =
  ## Real independent native resources, owned lookups and moves all retire before each allocation sample.
  var source = default(PagedReader)
  assert openPagedReader(source, directory, fixture.config).error == PagedNativeError.None
  var moved = move(source)
  assert not source.opened and moved.opened
  assert moved.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 7
  assert moved.lookup(pagedKey(64), pagedPolicy().work).error == PagedNativeError.UnknownKey
  assert moved.close == FileError.None
proc cycles(fixture: PagedNativeFixture) =
  ## One thousand complete open/verify/lookup/move/close lifetimes also exercise reacquisition after every pin retirement.
  var writer = default(PagedWriter)
  let directory = seeded(writer, "cycles", fixture)
  assert writer.close == FileError.None
  readerCycle(directory, fixture)
  let before = getOccupiedMem()
  for index in 0..<1000: readerCycle(directory, fixture)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_native", 1000, before, after)

proc writeFixture(name: string, bytes: seq[byte]) =
  ## Test-only transport writes are detached from measured native owner operations.
  var text = newString(bytes.len)
  for index in 0..<bytes.len: text[index] = char(bytes[index])
  try:
    # Fixture setup must fail explicitly rather than let missing data weaken a refusal assertion.
    writeFile(name, text)
  except:
    assert false, "native fixture write"
proc counterExhaustion(fixture: PagedNativeFixture) =
  ## Independently rehashed max counters must refuse before producer, hash or build IO is dispatched.
  for mode in 0..<2:
    let directory = path("counter-" & $mode)
    var native = default(PagedDirectory)
    assert openDirectory(native, directory, true, true) == FileError.None
    assert native.close == FileError.None
    var reference = pagedReference(fixture.config.chain, fixture.config.root, fixture.records)
    let epoch = if mode == 0: high(uint64) else: 1'u64
    reference.bytes.put(88, epoch)
    if mode == 1: reference.bytes.put(96, high(uint64))
    reference.recommit()
    writeFixture(directory & "/" & epochName(ManagedEpoch(epoch)).value, reference.bytes)
    writeFixture(directory & "/CURRENT", reference.manifest)
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
    resetIo()
    resetHash(0)
    let refused = preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
      uint64(fixture.records.len), fixture.payload)
    assert refused.error == PagedNativeError.CounterExhausted
    assert ioCalls(readIo) == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0
    assert hashCalls() == 0 and not candidate.opened
    assert writer.close == FileError.None
proc reclamationTrial(fixture: PagedNativeFixture, operation: cint, skip: int): array[3, uint64] =
  ## Retired cleanup separately qualifies pre-unlink failure, uncertain directory sync and post-confirmation close.
  result = default(array[3, uint64])
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  var candidate = default(PagedCandidate)
  let directory = seeded(writer, "reclaim-" & $operation & "-" & $skip, fixture)
  defer:
    resetIo()
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  let receipt = reader.epochReceipt.value
  assert reader.close == FileError.None
  prepare(writer, candidate, fixture)
  assert writer.publish(candidate).error == PagedNativeError.None
  let current = writer.selected.value
  resetIo()
  if operation != 0: armIo(operation, cint(skip), 1, failedIo)
  let removed = writer.reclaim(receipt, current)
  if operation == 0:
    # Baseline counts are observations of the genuine successful syscall path.
    assert removed.error == PagedNativeError.None
    result = [ioCalls(syncIo), ioCalls(unlinkIo), ioCalls(closeIo)]
  else:
    # Every scheduled refusal must execute; success is reserved for confirmed unlink followed by close failure.
    assert pendingIo() == 0
    if removed.error == PagedNativeError.None:
      assert operation == closeIo and removed.value.retirementError == FileError.IoFailure
    else:
      assert removed.error == PagedNativeError.FileFailure
  resetIo()
  assert writer.close == FileError.None
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  assert writer.reclaim(receipt, writer.selected.value).error == PagedNativeError.None
  assert writer.close == FileError.None
proc reclamationFaults(fixture: PagedNativeFixture) =
  ## Baseline observation sizes each independent barrier/unlink/retirement fault schedule.
  let counts = reclamationTrial(fixture, 0, 0)
  let operations = [syncIo, unlinkIo, closeIo]
  for index in 0..<operations.len:
    assert counts[index] > 0 and counts[index] < 20
    for skip in 0..<int(counts[index]): discard reclamationTrial(fixture, operations[index], skip)
proc crossProcessPin(fixture: PagedNativeFixture) =
  ## An exact stopped child holds a real shared epoch pin while the parent publishes and attempts reclamation.
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  var candidate = default(PagedCandidate)
  let directory = seeded(writer, "process-pin", fixture)
  defer:
    abortCrash()
    resetIo()
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  let receipt = reader.epochReceipt.value
  assert reader.close == FileError.None
  assert writer.close == FileError.None
  resetIo()
  let child = forkCrash(lockIo, 0)
  assert child >= 0
  if child == 0:
    # Arm only this child's reader acquisition; no writer lease or inherited pin survives fixture setup.
    if startCrash() != 0: exitCrash(81)
    if openPagedReader(reader, directory, fixture.config).error != PagedNativeError.None: exitCrash(82)
    exitCrash(0)
  assert waitCrash() == crashStopped
  assert openPagedWriter(writer, directory, fixture.config).error == PagedNativeError.None
  prepare(writer, candidate, fixture)
  assert writer.publish(candidate).error == PagedNativeError.None
  let blocked = writer.reclaim(receipt, writer.selected.value)
  assert blocked.error == PagedNativeError.FileFailure and blocked.fileError == FileError.Busy
  assert finishCrash() == crashKilled and crashCount() == 1
  resetIo()
  assert writer.reclaim(receipt, writer.selected.value).error == PagedNativeError.None
  assert writer.close == FileError.None
proc namespaceGuards(fixture: PagedNativeFixture) =
  ## Unknown staging bytes and receipts from another directory never authorize publication or deletion.
  var writer = default(PagedWriter)
  var other = default(PagedWriter)
  var reader = default(PagedReader)
  var candidate = default(PagedCandidate)
  let directory = seeded(writer, "namespace", fixture)
  let foreign = seeded(other, "foreign", fixture)
  defer:
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if other.opened: discard other.close
    if writer.opened: discard writer.close
  assert openPagedReader(reader, foreign, fixture.config).error == PagedNativeError.None
  let receipt = reader.epochReceipt.value
  assert reader.close == FileError.None
  prepare(writer, candidate, fixture)
  assert writer.publish(candidate).error == PagedNativeError.None
  let refused = writer.reclaim(receipt, writer.selected.value)
  assert refused.error == PagedNativeError.InvalidCandidate
  prepare(writer, candidate, fixture)
  writeFixture(directory & "/CURRENT.next", @[1'u8, 2, 3])
  let collision = writer.publish(candidate)
  assert collision.error == PagedNativeError.FileFailure and collision.fileError ==
      FileError.AlreadyExists
  assert uint64(writer.selected.value.sequence) == 1
  assert candidate.close == FileError.None
  assert writer.close == FileError.None
  assert other.close == FileError.None

proc renameNative(source, destination: cstring): cint {.importc: "rename", cdecl,
    header: "<stdio.h>".}
  ## Test-only namespace substitution keeps the original inode alive under a different name.
proc inodeSubstitution(fixture: PagedNativeFixture) =
  ## Equal independently valid bytes under another inode cannot revive an already captured reader or writer.
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  let directory = seeded(writer, "inode", fixture)
  defer:
    if reader.opened: discard reader.close
    if writer.opened: discard writer.close
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  let reference = pagedReference(fixture.config.chain, fixture.config.root, fixture.records)
  var original = directory & "/" & epochName(ManagedEpoch(1)).value
  var retained = directory & "/CAPTURED"
  assert renameNative(original.toCString(), retained.toCString()) == 0
  writeFixture(original, reference.bytes)
  assert reader.lookup(pagedKey(0), pagedPolicy().work).error == PagedNativeError.StreamFailure
  assert reader.selected.error == PagedNativeError.RecoveryRequired
  assert writer.selected.error == PagedNativeError.FileFailure
  assert writer.selected.error == PagedNativeError.RecoveryRequired
  assert reader.close == FileError.None
  assert writer.close == FileError.None
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  assert reader.lookup(pagedKey(0), pagedPolicy().work).value.bytes[0] == 7
  assert reader.close == FileError.None

proc lowLevelMoves() =
  ## Real file/directory owners move without copied close authority; file descriptors survive namespace-owner close.
  var directory = default(PagedDirectory)
  var file = default(PagedFile)
  let name = path("low-level-moves")
  assert openDirectory(directory, name, true, true) == FileError.None
  assert openEpoch(file, directory, ManagedEpoch(1), PagedPin.Create, pagedPolicy().dataset.bytes) == FileError.None
  var movedDirectory = move(directory)
  var movedFile = move(file)
  assert not directory.opened and not file.opened
  assert movedDirectory.close == FileError.None
  assert movedFile.check == FileError.None
  assert openDirectory(directory, name, false, true) == FileError.None
  assert directory.close == FileError.None
  assert movedFile.close == FileError.None

proc main() =
  ## Native positive control first proves SDK bindings and real flock/rename/fsync behavior.
  let old = nativeFixture(7)
  let fresh = nativeFixture(9)
  normal(old, fresh)
  policies(old)
  staleCandidate(old)
  publicationFaults(old)
  shortAndInterrupted(old)
  authoringFailure(old)
  counterExhaustion(old)
  reclamationFaults(old)
  crossProcessPin(old)
  namespaceGuards(old)
  inodeSubstitution(old)
  lowLevelMoves()
  cycles(old)
  echo "PASS native paged storage: durable selection, independent pins, retained readers and explicit reclamation"
main()
