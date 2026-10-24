# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native full-state selection binds sealed artifacts to exact writer/source incarnations and confirmed barriers.
# @@Verification={"arc":"storage_full_paged_publication_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, full_paged_reference, full_paged_native_fixture, storage_io]
import ../../../src/storage/[full_paged_codec, full_paged_stream, full_paged_build,
  full_paged_store,
  paged_io, managed_manifest, node_records, node_repository, file_errors, durability]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Primitive work counters distinguish integer-exhaustion preflight from attempted cryptography.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe real provider calls rather than interpreting a generic refusal as early validation.
proc path(label: string): string =
  ## Process-specific names confine all native namespaces to this suite's ignored working directory.
  "full-paged-publication-" & $storageProcessId() & "-" & label
proc normal(old, fresh: FullPagedFixture) =
  ## Readers survive writer replacement/close; ordinary generations advance exactly once per confirmed replacement.
  let directory = path("normal")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  var reader = default(FullPagedReader)
  var next = default(FullPagedReader)
  defer:
    resetIo()
    if next.opened: discard next.close
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, old)
  var transferred = move(writer)
  assert not writer.opened and transferred.opened
  writer = move(transferred)
  assert uint64(writer.selected.value.epoch) == 1
  assert uint64(writer.selected.value.generation) == 0
  assert openFullPagedReader(reader, directory, old.config).error == FullPagedNativeError.None
  let owned = reader.lookup(old.header.root, key(0)).value
  writer.prepare(candidate, fresh)
  var transfer = move(candidate)
  assert not candidate.opened and transfer.opened
  candidate = move(transfer)
  let published = writer.publish(candidate)
  assert published.error == FullPagedNativeError.None and not candidate.opened
  assert published.value.writerUsable and published.value.retirementError == FileError.None
  assert uint64(published.value.manifest.epoch) == 2
  assert uint64(published.value.manifest.generation) == 1
  assert reader.lookup(old.header.root, key(0)).value.bytes == @[7'u8]
  assert openFullPagedReader(next, directory, fresh.config).error == FullPagedNativeError.None
  assert next.lookup(fresh.header.root, key(0)).value.bytes == @[9'u8]
  assert writer.close == FileError.None
  assert owned.bytes == @[7'u8]
  assert next.close == FileError.None and reader.close == FileError.None
  assert openFullPagedWriter(writer, directory, fresh.config).error == FullPagedNativeError.None
  assert uint64(writer.selected.value.generation) == 1
  assert writer.close == FileError.None
  assert openFullPagedWriter(writer, directory, old.config).error != FullPagedNativeError.None
  assert not writer.opened
proc incarnation(fixture: FullPagedFixture) =
  ## Descriptor-number reuse cannot revive a sealed candidate after its original writer lease is retired.
  let directory = path("incarnation")
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  defer:
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  seed(writer, directory, fixture)
  writer.prepare(candidate, fixture)
  assert writer.close == FileError.None
  assert openFullPagedWriter(writer, directory, fixture.config).error == FullPagedNativeError.None
  assert writer.publish(candidate).error == FullPagedNativeError.StaleView
  assert uint64(writer.selected.value.epoch) == 1
  assert candidate.close == FileError.None and writer.close == FileError.None
proc faultSchedule(old, fresh: FullPagedFixture) =
  ## Every observed publication fault preserves either no new receipt or a separate confirmed retirement diagnostic.
  let operations = [readIo, writeIo, syncIo, renameIo, closeIo, lockIo, truncateIo]
  var counts = default(array[7, uint64])
  block baseline:
    # Capture only publication operations after durable source and sealed target preparation.
    var writer = default(FullPagedWriter)
    var candidate = default(FullPagedCandidate)
    defer:
      resetIo()
      if candidate.opened: discard candidate.close
      if writer.opened: discard writer.close
    seed(writer, path("fault-baseline"), old)
    writer.prepare(candidate, fresh)
    resetIo()
    assert writer.publish(candidate).error == FullPagedNativeError.None
    for index in 0..<operations.len: counts[index] = ioCalls(operations[index]) # Actual reached boundaries only.
  for operation in 0..<operations.len:
    # Fresh source/candidate names isolate each uncertainty branch from all preceding forensic prefixes.
    for skip in 0'u64..<counts[operation]:
      let directory = path("fault-" & $operation & "-" & $skip)
      var writer = default(FullPagedWriter)
      var candidate = default(FullPagedCandidate)
      var reader = default(FullPagedReader)
      defer:
        resetIo()
        if reader.opened: discard reader.close
        if candidate.opened: discard candidate.close
        if writer.opened: discard writer.close
      seed(writer, directory, old)
      writer.prepare(candidate, fresh)
      armIo(operations[operation], cint(skip), 1, failedIo)
      let published = writer.publish(candidate)
      assert pendingIo() == 0
      resetIo()
      if published.error == FullPagedNativeError.None:
        # Only post-confirmation close/adoption errors may accompany a successful durable new selection.
        assert not published.value.writerUsable and published.value.retirementError != FileError.None
      if candidate.opened: assert candidate.close == FileError.None
      assert writer.close == FileError.None
      let prior = openFullPagedReader(reader, directory, old.config)
      if prior.error == FullPagedNativeError.None:
        assert reader.lookup(old.header.root, key(0)).value.bytes == @[7'u8]
        assert reader.close == FileError.None
      else:
        # Failed final directory sync may leave the new CURRENT visible without returning its durability receipt.
        assert openFullPagedReader(reader, directory, fresh.config).error ==
            FullPagedNativeError.None
        assert reader.lookup(fresh.header.root, key(0)).value.bytes == @[9'u8]
        assert reader.close == FileError.None
proc counterExhaustion(source: FullPagedFixture) =
  ## Positive physical/generation maxima refuse a successor before hashing, allocation or candidate creation.
  for exhausted in 0..1:
    let epoch = if exhausted == 0: ManagedEpoch(high(uint64)) else: ManagedEpoch(1)
    let generation = if exhausted == 1: RepositoryGeneration(high(
        uint64)) else: RepositoryGeneration(0)
    let root = branch(leaf(0, @[7'u8]), leaf(128, @[]))
    let full = fixture(source.records, root, source.roots, epoch, generation)
    let directory = path("exhausted-" & $exhausted)
    var writer = default(FullPagedWriter)
    var candidate = default(FullPagedCandidate)
    defer:
      resetHash(0)
      if candidate.opened: discard candidate.close
      if writer.opened: discard writer.close
    seedOracle(directory, full)
    assert openFullPagedWriter(writer, directory, source.config).error == FullPagedNativeError.None
    resetHash(0)
    let refused = prepareFullPagedReplacement(writer, candidate, source.header.root, source.roots,
      source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes)
    assert refused.error == FullPagedNativeError.CounterExhausted and not candidate.opened
    assert hashCalls() == 0
    assert writer.close == FileError.None
proc bootstrapFaults(fixture: FullPagedFixture) =
  ## Initial creation is qualified separately from replacement so partial namespace/epoch prefixes remain forensic.
  let operations = [readIo, writeIo, syncIo, renameIo, closeIo, lockIo, truncateIo]
  var counts = default(array[7, uint64])
  block baseline:
    # Count only the complete bootstrap path, including target barriers, selection and post-confirmation adoption.
    var writer = default(FullPagedWriter)
    resetIo()
    seed(writer, path("initial-control"), fixture)
    for index in 0..<operations.len: counts[index] = ioCalls(operations[index])
    resetIo()
    assert writer.close == FileError.None
  for channel in 0..<operations.len:
    for skip in 0'u64..<counts[channel]:
      # Each fault gets an independent newly created namespace and one explicit writer close obligation.
      let directory = path("initial-" & $channel & "-" & $skip)
      var writer = default(FullPagedWriter)
      var reader = default(FullPagedReader)
      defer:
        resetIo()
        if reader.opened: discard reader.close
        if writer.opened: discard writer.close
      armIo(operations[channel], cint(skip), 1, failedIo)
      let initialized = initializeFullPagedWriter(writer, directory, fixture.config, fixture.roots,
        fixture.records.producer, fixture.header.geometry.entries,
        fixture.header.geometry.payloadBytes)
      assert pendingIo() == 0
      resetIo()
      if initialized.error == FullPagedNativeError.None:
        # Confirmed bootstrap selection may retain only a separately reported native retirement failure.
        assert not initialized.value.writerUsable and initialized.value.retirementError != FileError.None
      if writer.opened: assert writer.close == FileError.None
      let opened = openFullPagedReader(reader, directory, fixture.config)
      if opened.error == FullPagedNativeError.None:
        assert reader.lookup(fixture.header.root, key(0)).value.bytes == @[7'u8]
        assert reader.close == FileError.None
proc lifecycle(directory: string, fixture: FullPagedFixture) =
  ## Repeated strict writer open and independent reader lifetime retain no process-native owner or graph.
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  assert openFullPagedWriter(writer, directory, fixture.config).error == FullPagedNativeError.None
  assert openFullPagedReader(reader, directory, fixture.config).error == FullPagedNativeError.None
  assert writer.close == FileError.None
  assert reader.lookup(fixture.header.root, key(0)).value.bytes.len == 1
  assert reader.close == FileError.None
proc main() =
  ## Checked native publication tests preserve all forensic files under the isolated runner directory.
  let old = sample(7)
  let fresh = sample(9)
  normal(old, fresh)
  incarnation(old)
  counterExhaustion(old)
  bootstrapFaults(old)
  faultSchedule(old, fresh)
  let directory = path("cycles")
  var writer = default(FullPagedWriter)
  seed(writer, directory, old)
  assert writer.close == FileError.None
  lifecycle(directory, old)
  let before = getOccupiedMem()
  for iteration in 0..<1000: lifecycle(directory, old)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_publication", 1000, before, after)
  var persistent = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  var retained = default(FullPagedReader)
  assert openFullPagedWriter(persistent, directory, old.config).error == FullPagedNativeError.None
  assert openFullPagedReader(retained, directory, old.config).error == FullPagedNativeError.None
  persistent.prepare(candidate, old)
  assert persistent.publish(candidate).error == FullPagedNativeError.None
  let retainedBytes = getOccupiedMem()
  for iteration in 0..<1000:
    # Ordinary explicit replacements retire every candidate and prior selected descriptor without growing a history graph.
    persistent.prepare(candidate, old)
    assert persistent.publish(candidate).error == FullPagedNativeError.None
  assert getOccupiedMem() == retainedBytes
  assert uint64(retained.selected.value.epoch) == 1
  assert retained.lookup(old.header.root, key(0)).value.bytes == @[7'u8]
  assert retained.close == FileError.None and persistent.close == FileError.None
  echo "storage full paged publication PASS"
main()
