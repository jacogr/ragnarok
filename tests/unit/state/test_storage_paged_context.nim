# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent V2 bytes and native fault/replay controls bind light context without granting complete-map authority.
# @@Verification={"arc":"storage_paged_context_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../support/storage_paged_reference
import ../../support/storage_paged_native_fixture
import ../../../src/storage/paged_stream as storage_paged_stream
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/paged_store as storage_paged_store
import ../../../src/storage/paged_io as storage_paged_io
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/storage/durability as storage_durability
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/state/paged_proof_view as state_paged_proof_view
import ../../../src/state/proof_view as state_proof_view
type Memory = ref object ## Only the independent test transport retains a resident artifact and fault counters.
  bytes: seq[byte]
  calls, failAt: int
proc path(label: string): string =
  ## Every native trial owns its namespace under the ignored runner directory.
  "paged-context-" & $storageProcessId() & "-" & label
proc body(size: int, first = 7): seq[byte] =
  ## Fixture bytes cross page boundaries independently of proof payloads.
  result = newSeq[byte](size)
  for index in 0..<size: result[index] = byte((index+first) mod 251) # Bounded test-only arithmetic.
proc config(source: PagedNativeFixture, maximum = 65537'u64): PagedNativeConfig =
  ## Opaque context, total artifact, scratch and proof policies remain separate finite channels.
  result = source.config
  result.limits.contextBytes = ByteLimit(maximum)
  result.limits.workingBytes = ByteLimit(32000000)
proc input(memory: Memory): PagedInput =
  ## Exact synchronous callbacks never retain the supplied mutable output buffer.
  proc read(offset: PagedOffset, output: var openArray[byte]): bool {.closure.} =
    ## A late failed callback cannot publish any previously copied prefix.
    inc memory.calls
    if memory.calls == memory.failAt: return false
    let start = uint64(offset)
    if start > uint64(memory.bytes.len) or uint64(output.len) > uint64(
        memory.bytes.len)-start: return false
    for index in 0..<output.len: output[index] = memory.bytes[int(start)+index] # Independently bounded extent.
    true
  proc extent(output: var uint64): bool {.closure.} =
    ## EOF participates in failure injection before and after every owned capture.
    inc memory.calls
    output = uint64(memory.bytes.len)
    memory.calls != memory.failAt
  PagedInput(read: read, extent: extent)
proc output(memory: Memory): PagedOutput =
  ## The test sink permits only exact sequential appends, matching the production transport boundary.
  proc append(bytes: openArray[byte]): bool {.closure.} =
    ## Construction never gets direct access to the oracle or mutable resident source.
    for octet in bytes: memory.bytes.add(octet) # Owned test-only artifact.
    true
  PagedOutput(source: memory.input, append: append)
proc manifest(reference: PagedReference, source: PagedNativeFixture,
    limits: PagedStreamLimits): PagedManifest =
  ## Independent CURRENT bytes are decoded under explicit chain, root and V2 format policy.
  let decoded = decodePagedManifest(reference.manifest, source.config.chain, source.config.root,
    limits.dataset, ByteLimit(PagedManifestBytes), true)
  assert decoded.error == PagedCodecError.None
  decoded.value
proc header(source: PagedNativeFixture, selected: PagedNativeConfig, size: int, epoch = 1'u64,
    sequence = 0'u64): PagedHeader =
  ## Native target metadata comes only from independently supplied fixture expectations.
  initPagedHeader(selected.chain, selected.root, ManagedEpoch(epoch), LightDeltaSequence(sequence),
    uint64(source.records.len), source.payload, selected.limits.dataset, uint64(size)).value
proc write(path: string, bytes: seq[byte]) =
  ## Only explicitly owned fixture names are replaced for corruption and interrupted-prefix controls.
  var text = newString(bytes.len)
  for index in 0..<bytes.len: text[index] = char(bytes[index]) # Exact byte transport.
  try: writeFile(path, text)
  except: assert false # Fixture IO failure invalidates the trial.
proc initialize(writer: var PagedWriter, directory: string, source: PagedNativeFixture,
    selected: PagedNativeConfig, context: seq[byte]) =
  ## No ordinary consumer starts until both native durability barriers report success.
  let initialized = initializePagedWriter(writer, directory, selected,
    source.records.nativeProducer,
    uint64(source.records.len), source.payload, context)
  assert initialized.error == PagedNativeError.None
  assert initialized.value.durability == StorageDurability.FileAndDirectorySynced
  assert initialized.value.writerUsable and initialized.value.retirementError == FileError.None
proc lowLevel(source: PagedNativeFixture) =
  ## Whole-artifact oracle comparisons qualify both caches, empty knowledge and maximum context transport.
  for size in [1, 31, 4095, 4096, 4097, 65537, 4194304]:
    # Every boundary is independent of proof payload length and JAM value policy.
    let context = body(size)
    let selected = config(source, uint64(size))
    let reference = pagedReference(selected.chain, selected.root, source.records, context)
    for cache in 0..1:
      # Rebuild under a fresh transport rather than reusing already admitted metadata.
      var limits = selected.limits
      limits.cachePages = ElementLimit(cache)
      let memory = Memory()
      let built = buildPagedArtifact(memory.output, source.records.nativeProducer,
        header(source, selected, size), limits, context)
      assert built.error == PagedStreamError.None
      assert memory.bytes == reference.bytes
      assert built.value.manifest.bytes == reference.manifest
      let captured = readPagedContext(memory.input, built.value, limits.work)
      assert captured.error == PagedStreamError.None
      assert captured.value.bytes == context and captured.value.byteLength == size
      assert captured.value.manifest.bytes == reference.manifest
      var detached = captured.value.bytes
      detached[0] = detached[0] xor 1
      assert captured.value.bytes == context
      assert lookupPaged(built.value, memory.input, pagedKey(128),
          limits.work).value.verified.bytes.len == 0
      assert lookupPaged(built.value, memory.input, pagedKey(255),
          limits.work).value.verified.kind == StateLookupKind.Absent
      assert lookupPaged(built.value, memory.input, pagedKey(32), limits.work).error ==
          PagedStreamError.UnknownKey
      if size == 4194304:
        # Linear admission may fit a budget that authenticated random extraction cannot; callers cannot enlarge it.
        limits.work.ioCalls = ElementLimit(built.value.counts.ioCalls)
        let admitted = validatePagedArtifact(memory.input, reference.manifest(source, limits), limits)
        assert admitted.error == PagedStreamError.None
        assert readPagedContext(memory.input, admitted.value, selected.limits.work).error ==
            PagedStreamError.LimitExceeded
  let context = body(65537)
  var selected = config(source)
  let reference = pagedReference(selected.chain, selected.root, source.records, context)
  let memory = Memory(bytes: reference.bytes)
  selected.limits.workingBytes = ByteLimit(PagedStreamFixedBytes+41+4*uint64(context.len))
  let admitted = validatePagedArtifact(memory.input, reference.manifest(source, selected.limits),
      selected.limits)
  assert admitted.error == PagedStreamError.None
  let captured = readPagedContext(memory.input, admitted.value, selected.limits.work).value
  let counts = captured.counts
  var exact = selected.limits.work
  exact.ioCalls = ElementLimit(counts.ioCalls)
  exact.pageHashes = ElementLimit(counts.pageHashes)
  exact.readBytes = ByteLimit(counts.readBytes)
  assert readPagedContext(memory.input, admitted.value, exact).error == PagedStreamError.None
  for channel in 0..<3:
    # Independently shorten each actually used channel; no successful prefix may escape.
    var short = exact
    case channel
    of 0: short.ioCalls = ElementLimit(counts.ioCalls-1)
    of 1: short.pageHashes = ElementLimit(counts.pageHashes-1)
    else: short.readBytes = ByteLimit(counts.readBytes-1)
    assert readPagedContext(memory.input, admitted.value, short).error ==
        PagedStreamError.LimitExceeded
  selected.limits.workingBytes = ByteLimit(uint64(selected.limits.workingBytes)-1)
  let short = validatePagedArtifact(memory.input, reference.manifest(source, selected.limits),
      selected.limits).value
  memory.calls = 0
  assert readPagedContext(memory.input, short, exact).error == PagedStreamError.LimitExceeded
  assert memory.calls == 0
  selected.limits.contextBytes = ByteLimit(uint64(context.len)-1)
  assert validatePagedArtifact(memory.input, reference.manifest(source, selected.limits),
      selected.limits).error == PagedStreamError.LimitExceeded
  var empty = source
  empty.records = @[]
  empty.payload = 0
  let limits = config(empty).limits
  let memoryEmpty = Memory()
  let builtEmpty = buildPagedArtifact(memoryEmpty.output, empty.records.nativeProducer,
    header(empty, config(empty), 1), limits, body(1)).value
  assert lookupPaged(builtEmpty, memoryEmpty.input, pagedKey(0), limits.work).error ==
      PagedStreamError.UnknownKey
  assert readPagedContext(memoryEmpty.input, builtEmpty, limits.work).value.bytes == body(1)
proc normal(old, fresh: PagedNativeFixture) =
  ## One CURRENT binds exact context, proof availability and explicit root advancement while old pins remain immutable.
  let directory = path("normal")
  let before = body(4097)
  let after = body(33, 9)
  let selected = config(old)
  let destination = config(fresh)
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  var newest = default(PagedReader)
  var candidate = default(PagedCandidate)
  defer:
    # Native resources retire explicitly even when an assertion or IO failure interrupts the workload.
    resetIo()
    if candidate.opened: discard candidate.close
    if newest.opened: discard newest.close
    if reader.opened: discard reader.close
    if writer.opened: discard writer.close
  initialize(writer, directory, old, selected, before)
  assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
  var viewLimits = default(state_paged_proof_view.PagedProofViewLimits)
  viewLimits.proof.nodes = ElementLimit(249)
  viewLimits.proof.valueBytes = ByteLimit(10000)
  viewLimits.batch.items = ElementLimit(3)
  viewLimits.batch.nodes = ElementLimit(747)
  viewLimits.batch.valueBytes = ByteLimit(10000)
  viewLimits.view.items = ElementLimit(3)
  viewLimits.view.valueBytes = ByteLimit(10000)
  viewLimits.work = selected.limits.work
  let view = state_paged_proof_view.readPagedProofView(reader, selected.root,
    [pagedKey(0), pagedKey(128), pagedKey(255)], viewLimits).value
  assert view.lookup(pagedKey(0)).value.bytes[0] == 7
  assert view.lookup(pagedKey(128)).value.present and view.lookup(pagedKey(128)).value.bytes.len == 0
  assert not view.lookup(pagedKey(255)).value.present
  assert view.lookup(pagedKey(32)).error == state_proof_view.ProofViewError.MissingWitness
  assert state_paged_proof_view.readPagedProofView(reader, selected.root, [pagedKey(32)],
      viewLimits).error ==state_paged_proof_view.PagedProofViewError.MissingWitness
  let retained = reader.readContext(selected.limits.work).value
  let receipt = reader.epochReceipt.value
  assert preparePagedReplacement(writer, candidate, old.records.nativeProducer,
    uint64(old.records.len), old.payload, after).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.sequence) == 1
  assert writer.readContext(selected.limits.work).value.bytes == after
  assert reader.readContext(selected.limits.work).value.bytes == before
  assert writer.reclaim(receipt, writer.selected.value).fileError == FileError.Busy
  assert preparePagedAdvance(writer, candidate, destination.root, fresh.records.nativeProducer,
    uint64(fresh.records.len), fresh.payload, before).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.sequence) == 1 and uint64(writer.selected.value.epoch) == 3
  assert openPagedReader(newest, directory, destination).error == PagedNativeError.None
  assert newest.lookup(pagedKey(0), destination.limits.work).value.bytes[0] == 9
  assert newest.lookup(pagedKey(32), destination.limits.work).error == PagedNativeError.UnknownKey
  assert preparePagedCompaction(writer, candidate).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.epoch) == 4 and uint64(writer.selected.value.sequence) == 1
  assert writer.readContext(destination.limits.work).value.bytes == before
  assert reader.close == FileError.None
  assert writer.reclaim(receipt, writer.selected.value).error == PagedNativeError.None
  assert retained.bytes == before
  assert newest.close == FileError.None
  assert writer.close == FileError.None
  assert openPagedReader(reader, directory, selected).error == PagedNativeError.FileFailure
  assert openPagedReader(reader, directory, destination).error == PagedNativeError.None
  assert reader.readContext(destination.limits.work).value.bytes == before
  assert reader.close == FileError.None
proc replay(source: PagedNativeFixture) =
  ## Same-root compaction cleanup also binds opaque context, including prefixes that contain no context page yet.
  let selected = config(source)
  let context = body(4097)
  for compaction in [false, true]:
    # A target prefix before context cannot by itself distinguish two independently replayed context choices.
    let directory = path("replay-" & $compaction)
    var writer = default(PagedWriter)
    var candidate = default(PagedCandidate)
    initialize(writer, directory, source, selected, context)
    let sourceHead = writer.selected.value
    let sequence = if compaction: 0'u64 else: 1'u64
    let expected = header(source, selected, context.len, 2, sequence)
    var reference = pagedReference(selected.chain, selected.root, source.records, context, 2, sequence)
    reference.bytes.setLen(1)
    write(directory & "/" & epochName(ManagedEpoch(2)).value, reference.bytes)
    let wrong = preparePagedCleanup(writer, candidate, sourceHead, expected,
      source.records.nativeProducer, body(context.len, 9))
    if compaction:
      assert wrong.error == PagedNativeError.InvalidTransition # Source context equality is mandatory despite an ambiguous forensic prefix.
    else:
      # Replacement context comes from independent caller intent, so a matching tiny prefix permits either explicit target.
      assert wrong.error == PagedNativeError.None
      assert candidate.close == FileError.None
    assert preparePagedCleanup(writer, candidate, sourceHead, expected,
      source.records.nativeProducer, context).error == PagedNativeError.None
    assert discardPagedCandidate(writer, candidate, sourceHead).error == PagedNativeError.None
    assert writer.readContext(selected.limits.work).value.bytes == context
    assert writer.close == FileError.None
proc corruption(source: PagedNativeFixture) =
  ## Authentication and canonical padding checks reject both unrecommitted and independently recommitted tampering.
  let selected = config(source)
  let context = body(4097)
  for kind in 0..<3:
    # Each corruption starts from an independent complete oracle rather than a previously mutated backing sequence.
    var reference = pagedReference(selected.chain, selected.root, source.records, context)
    let shape = header(source, selected, context.len).geometry
    case kind
    of 0: reference.bytes[int(uint64(shape.contextOffset))] = reference.bytes[int(uint64(
        shape.contextOffset))] xor 1
    of 1:
      reference.bytes[int(uint64(shape.contextOffset))+context.len] = 1
      reference.recommit()
    else:
      reference.bytes[int(uint64(shape.payloadOffset)+shape.payloadBytes)] = 1
      reference.recommit()
    let checked = validatePagedArtifact(Memory(bytes: reference.bytes).input,
      reference.manifest(source, selected.limits), selected.limits)
    if kind == 0: assert checked.error == PagedStreamError.ChecksumMismatch # Actual context bytes are authenticated.
    else: assert checked.error == PagedStreamError.InvalidFormat # Rehashed noncanonical suffixes remain forbidden.
proc faults(source: PagedNativeFixture) =
  ## Every actually observed native context read and candidate write boundary is exercised with fresh owners.
  let selected = config(source)
  let context = body(4097)
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  var candidate = default(PagedCandidate)
  let directory = path("fault-reads")
  initialize(writer, directory, source, selected, context)
  assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
  resetIo()
  assert reader.readContext(selected.limits.work).value.bytes == context
  let reads = ioCalls(readIo)
  for skip in 0..<int(reads):
    # Native uncertainty latches until explicit close/reopen; no failed context is returned.
    armIo(readIo, cint(skip), 1, failedIo)
    assert reader.readContext(selected.limits.work).error == PagedNativeError.StreamFailure
    assert pendingIo() == 0
    resetIo()
    assert reader.readContext(selected.limits.work).error == PagedNativeError.RecoveryRequired
    assert reader.close == FileError.None
    assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
  assert reader.close == FileError.None
  resetIo()
  assert preparePagedReplacement(writer, candidate, source.records.nativeProducer,
    uint64(source.records.len), source.payload, context).error == PagedNativeError.None
  let writes = ioCalls(writeIo)
  assert candidate.close == FileError.None
  assert writer.close == FileError.None
  for skip in 0..<int(writes):
    # Independent namespaces preserve every failed forensic prefix and the exact old CURRENT context.
    let trial = path("fault-write-" & $skip)
    initialize(writer, trial, source, selected, context)
    let old = writer.selected.value.bytes
    armIo(writeIo, cint(skip), 1, failedIo)
    let failed = preparePagedReplacement(writer, candidate, source.records.nativeProducer,
      uint64(source.records.len), source.payload, body(context.len, 9))
    assert pendingIo() == 0 and failed.error != PagedNativeError.None
    resetIo()
    assert writer.selected.value.bytes == old # Failure never publishes a new selection.
    assert writer.readContext(selected.limits.work).value.bytes == context
    if candidate.opened: assert candidate.close == FileError.None
    assert writer.close == FileError.None
proc refusals(source: PagedNativeFixture) =
  ## Presence/cap policy refuses bootstrap before namespace creation; V1 cannot open a selected V2 artifact.
  let selected = config(source)
  let context = body(4097)
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  let missing = initializePagedWriter(writer, path("missing"), selected,
    source.records.nativeProducer, uint64(source.records.len), source.payload)
  assert missing.error == PagedNativeError.StreamFailure and missing.streamError ==
      PagedStreamError.UnsupportedPolicy
  assert not writer.opened
  let unexpected = initializePagedWriter(writer, path("unexpected"), source.config,
    source.records.nativeProducer, uint64(source.records.len), source.payload, context)
  assert unexpected.error == PagedNativeError.StreamFailure and unexpected.streamError ==
      PagedStreamError.UnsupportedPolicy
  assert not writer.opened
  let directory = path("refusals")
  initialize(writer, directory, source, selected, context)
  assert writer.close == FileError.None
  assert openPagedReader(reader, directory, source.config).error == PagedNativeError.FileFailure
  assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
  resetIo()
  let quota = reader.readContext(default(PagedWorkLimits))
  assert quota.error == PagedNativeError.StreamFailure and quota.streamError ==
      PagedStreamError.LimitExceeded
  assert ioCalls(readIo) == 0
  assert reader.close == FileError.None
  assert reader.readContext(selected.limits.work).error == PagedNativeError.Uninitialized
proc bootstrap(source: PagedNativeFixture) =
  ## Explicit initial replay requires the same independent context after a real interrupted append.
  let selected = config(source)
  let context = body(4097)
  let directory = path("bootstrap")
  var writer = default(PagedWriter)
  armIo(writeIo, 1, 1, failedIo)
  let failed = initializePagedWriter(writer, directory, selected, source.records.nativeProducer,
    uint64(source.records.len), source.payload, context)
  assert failed.error != PagedNativeError.None and pendingIo() == 0
  resetIo()
  assert writer.close == FileError.None
  let resumed = resumePagedInitialization(writer, directory, selected,
    source.records.nativeProducer,
    uint64(source.records.len), source.payload, context)
  assert resumed.error == PagedNativeError.None
  assert writer.readContext(selected.limits.work).value.bytes == context
  assert writer.close == FileError.None
proc cycle(reader: var PagedReader, directory: string, selected: PagedNativeConfig,
    context: seq[byte], late: cint) =
  ## Repeated success, detached getter mutation and late failed-prefix allocation all release before fresh reopen.
  let captured = reader.readContext(selected.limits.work).value
  var detached = captured.bytes
  detached[0] = detached[0] xor 1
  assert captured.bytes == context
  armIo(readIo, late, 1, failedIo)
  let failed = reader.readContext(selected.limits.work)
  assert failed.error == PagedNativeError.StreamFailure and pendingIo() == 0
  resetIo()
  assert reader.close == FileError.None
  assert captured.bytes == context
  assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
proc main() =
  ## Checked native ARC evidence includes allocations released after partially copied context failures.
  let old = nativeFixture(7)
  let fresh = nativeFixture(9)
  lowLevel(old)
  normal(old, fresh)
  replay(old)
  corruption(old)
  faults(old)
  refusals(old)
  bootstrap(old)
  let selected = config(old)
  let context = body(4097)
  let directory = path("cycles")
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  initialize(writer, directory, old, selected, context)
  assert writer.close == FileError.None
  assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
  resetIo()
  assert reader.readContext(selected.limits.work).value.bytes == context
  let calls = ioCalls(readIo)
  assert calls > 0 and calls <= uint64(high(cint))
  cycle(reader, directory, selected, context, cint(calls-1))
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Fresh native admission prevents a stale file or cached transport from hiding a leaked failure prefix.
    cycle(reader, directory, selected, context, cint(calls-1))
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_context", 1000, before, after)
  assert reader.close == FileError.None
  echo "storage paged context PASS"
main()
