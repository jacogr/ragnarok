# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full V2 artifacts atomically select opaque context with complete roots, preserving native ownership and replay authority.
# @@Verification={"arc":"storage_full_paged_context_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, full_paged_reference, full_paged_native_fixture]
import ../../../src/storage/full/paged/[codec as full_paged_codec, stream as full_paged_stream,
    build as full_paged_build, store as full_paged_store]
import ../../../src/storage/paged/[codec as paged_codec, stream as paged_stream, io as paged_io]
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/durability
import ../../../src/storage/file/errors as file_errors
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc path(label: string): string =
  ## Process-private test namespaces remain under the ignored native runner directory.
  "full-paged-context-" & $storageProcessId() & "-" & label
proc body(size: int, first = 7'u8): seq[byte] =
  ## Deterministic context bytes cross every page boundary without borrowing any state value buffer.
  result = newSeq[byte](size)
  for index in 0..<size: result[index] = byte((index+int(first)) mod 251) # Bounded fixture arithmetic.
proc configuration(source: FullPagedFixture, maximum = 65537'u64): FullPagedNativeConfig =
  ## Context, artifact, native working and authoring quotas are explicit independent local policies.
  result = source.config
  result.limits.contextBytes = ByteLimit(maximum)
  result.limits.dataset.bytes = ByteLimit(16000000)
  result.limits.workingBytes = ByteLimit(32000000)
  result.limits.work.readBytes = ByteLimit(256000000)
  result.limits.work.writeBytes = ByteLimit(16000000)
  result.construction.ioCalls = ElementLimit(1000000)
  result.construction.hashes = ElementLimit(1000000)
  result.construction.readBytes = ByteLimit(256000000)
  result.construction.writeBytes = ByteLimit(16000000)
  result.replayBytes = ByteLimit(16000000)
proc expected(source: FullPagedFixture, context: seq[byte], epoch, generation: uint64,
    limits: PagedLimits): FullPagedFixture =
  ## Existing independent record bytes plus a separately computed context section/tree form the full artifact oracle.
  let header = initFullPagedHeader(source.header.chainId, source.header.root, ManagedEpoch(epoch),
    RepositoryGeneration(generation), source.header.geometry.entries,
        source.header.geometry.payloadBytes,
    source.roots, limits, uint64(context.len)).value
  let records = source.header.geometry.entries
  let payload = source.header.geometry.payloadBytes
  let start = (1+(records*64+4095) div 4096+(payload+4095) div 4096)*4096
  let pages = start div 4096+uint64((context.len+4095) div 4096)
  var leaves = 1'u64
  while leaves < pages: leaves *= 2 # The fixed finite fixture plan keeps these independent products small.
  var bytes = newSeq[byte](int(start))
  for index in 0..<bytes.len: bytes[index] = source.io.bytes[
      index] # Preserve independent exact index/payload and padding.
  let prefix = header.bytes
  for index in 0..<4096: bytes[index] = prefix[index] # V2 fields already have independent whole-header codec witnesses.
  for octet in context: bytes.add(octet) # The native builder is not involved in expected context placement.
  while uint64(bytes.len) < pages*4096: bytes.add(0) # Canonical context-only padding.
  let root = tree(bytes, int(pages), 0, int(leaves))
  assert uint64(bytes.len) == header.geometry.byteLength
  FullPagedFixture(header: header, manifest: encodeFullPagedManifest(header, FullPagedDigest(
      root)).value,
    records: source.records, io: FullPagedTestIO(bytes: bytes))
proc output(io: FullPagedTestIO): PagedOutput =
  ## A resident test sink exposes actual callback failures without replacing any production encoding or hashing.
  proc append(input: openArray[byte]): bool {.closure.} =
    ## Failed writes may retain forensic prefixes; a successful artifact must never follow them.
    inc io.calls
    if io.calls == io.failAt: return false
    for octet in input: io.bytes.add(octet) # Append the exact borrowed extent.
    true
  PagedOutput(source: io.input, append: append)
proc limits(config: FullPagedNativeConfig): FullPagedBuildLimits =
  ## The same finite native authoring contract also qualifies low-level callback transport.
  FullPagedBuildLimits(admission: config.limits, producerCalls: config.construction.producerCalls,
    ioCalls: config.construction.ioCalls, hashes: config.construction.hashes,
    readBytes: config.construction.readBytes, writeBytes: config.construction.writeBytes)
proc text(input: openArray[byte]): string =
  ## Native fixture files preserve every octet without text encoding transformations.
  result = newString(input.len)
  for index in 0..<input.len: result[index] = char(input[index]) # Direct test-only bytes.
proc write(path: string, bytes: openArray[byte]) =
  ## Only explicitly owned fixture paths may be replaced to qualify strict corruption refusal.
  try: writeFile(path, text(bytes))
  except: assert false # A failed fixture write cannot masquerade as successful tampering.
proc read(path: string): string =
  ## Native file observations stay separate from the independently constructed expected bytes.
  try: result = readFile(path)
  except: assert false # Missing or failed native reads invalidate the test.
proc initialize(writer: var FullPagedWriter, directory: string, source: FullPagedFixture,
    config: FullPagedNativeConfig, context: seq[byte]) =
  ## A confirmed file/directory barrier is required before any ordinary native consumer runs.
  let initialized = initializeFullPagedWriter(writer, directory, config, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes, context)
  assert initialized.error == FullPagedNativeError.None
  assert initialized.value.durability == StorageDurability.FileAndDirectorySynced
  assert initialized.value.retirementError == FileError.None and initialized.value.writerUsable
proc lowLevel(source: FullPagedFixture) =
  ## Cross-page and maximum-sized contexts match an independent complete byte/tree oracle under both cache settings.
  for size in [1, 31, 4095, 4096, 4097, 65537, 4194304]:
    # Context byte retention is caller-bounded separately from record/value and total dataset size.
    let context = body(size)
    let config = configuration(source, uint64(size))
    let oracle = expected(source, context, 1, 0, config.limits.dataset)
    for cache in 0..1:
      # Fresh construction/admission uses only fixed page buffers even though the test oracle is resident.
      var selected = config
      selected.limits.cachePages = ElementLimit(cache)
      let io = FullPagedTestIO()
      let built = buildFullPaged(io.output, FullPagedTestIO(bytes: newSeq[byte](6)).scratch,
        source.records.producer, oracle.header, limits(selected), context)
      assert built.error == FullPagedBuildError.None
      assert io.bytes == oracle.io.bytes
      let captured = readFullPagedContext(io.input, built.value.checked, selected.limits.work)
      assert captured.error == FullPagedStreamError.None and captured.value.bytes == context
      assert captured.value.manifest.bytes.value == oracle.manifest.bytes.value
      var detached = captured.value.bytes
      detached[0] = detached[0] xor 1
      assert captured.value.bytes == context
      assert captured.value.byteLength == size
      if size == 4194304:
        # Authenticated random context reads can cost more IO than linear admission; callers cannot relax captured policy.
        var bounded = selected.limits
        bounded.work.ioCalls = ElementLimit(built.value.checked.counts.ioCalls)
        let admitted = oracle.check(bounded)
        assert admitted.error == FullPagedStreamError.None
        assert readFullPagedContext(oracle.io.input, admitted.value, selected.limits.work).error ==
            FullPagedStreamError.LimitExceeded
  let context = body(65537)
  var config = configuration(source, uint64(context.len))
  let oracle = expected(source, context, 1, 0, config.limits.dataset)
  config.limits.workingBytes = ByteLimit(FullPagedFixedBytes+4*uint64(context.len))
  let checked = oracle.check(config.limits).value
  let captured = readFullPagedContext(oracle.io.input, checked, config.limits.work).value
  let counts = captured.counts
  let exact = FullPagedWorkLimits(ioCalls: ElementLimit(counts.ioCalls), hashes: ElementLimit(
      counts.hashes),
    readBytes: ByteLimit(counts.readBytes))
  assert readFullPagedContext(oracle.io.input, checked, exact).error == FullPagedStreamError.None
  for channel in 0..<3:
    # Each independent exact native work ceiling refuses at one short without a completed context prefix.
    var short = exact
    case channel
    of 0: short.ioCalls = ElementLimit(counts.ioCalls-1)
    of 1: short.hashes = ElementLimit(counts.hashes-1)
    else: short.readBytes = ByteLimit(counts.readBytes-1)
    assert readFullPagedContext(oracle.io.input, checked, short).error ==
        FullPagedStreamError.LimitExceeded
  config.limits.workingBytes = ByteLimit(FullPagedFixedBytes+4*uint64(context.len)-1)
  let short = oracle.check(config.limits).value
  oracle.io.calls = 0
  assert readFullPagedContext(oracle.io.input, short, config.limits.work).error ==
      FullPagedStreamError.LimitExceeded
  assert oracle.io.calls == 0
  config.limits.contextBytes = ByteLimit(uint64(context.len)-1)
  assert oracle.check(config.limits).error == FullPagedStreamError.LimitExceeded
proc normal(source, history: FullPagedFixture) =
  ## Context/root publication, retained old readers and exact page-wise compaction share one CURRENT decision.
  let directory = path("normal")
  let before = body(4097, 7)
  let after = body(33, 9)
  let config = configuration(source)
  let nextConfig = configuration(history)
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  var newest = default(FullPagedReader)
  var candidate = default(FullPagedCandidate)
  defer:
    # Native close obligations remain explicit on every path, including IO-poisoned owners.
    resetIo()
    if newest.opened: discard newest.close
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  initialize(writer, directory, source, config, before)
  let initial = expected(source, before, 1, 0, config.limits.dataset)
  assert read(directory & "/CURRENT") == text(initial.manifest.bytes.value)
  assert read(directory & "/" & epochName(ManagedEpoch(1)).value) == text(initial.io.bytes)
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  let retained = reader.readContext(config.limits.work).value
  let oldReceipt = reader.epochReceipt.value
  var narrower = config
  narrower.limits.contextBytes = ByteLimit(uint64(config.limits.contextBytes)-1)
  var other = default(FullPagedReader)
  assert openFullPagedReader(other, directory, narrower).error == FullPagedNativeError.None
  let wrongPolicy = other.epochReceipt.value
  assert other.close == FileError.None
  assert retained.bytes == before
  assert retained.manifest.bytes.value == reader.selected.value.bytes.value
  assert writer.readContext(config.limits.work).value.bytes == before
  let staged = prepareFullPagedReplacement(writer, candidate, history.header.root, history.roots,
    history.records.producer, history.header.geometry.entries, history.header.geometry.payloadBytes, after)
  assert staged.error == FullPagedNativeError.None
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert openFullPagedReader(newest, directory, nextConfig).error == FullPagedNativeError.None
  let captured = newest.readContext(config.limits.work).value
  assert captured.bytes == after
  assert newest.lookup(source.header.root, key(0)).value.bytes == @[7'u8]
  assert newest.lookup(history.header.root, key(0)).value.bytes == @[9'u8]
  assert prepareFullPagedCompaction(writer, candidate).error == FullPagedNativeError.None
  assert writer.publish(candidate).error == FullPagedNativeError.None
  let compacted = expected(history, after, 3, 1, config.limits.dataset)
  assert read(directory & "/CURRENT") == text(compacted.manifest.bytes.value)
  assert read(directory & "/" & epochName(ManagedEpoch(3)).value) == text(compacted.io.bytes)
  assert writer.readContext(config.limits.work).value.bytes == after
  assert openFullPagedEpochReader(other, directory, config, retained.manifest).error ==
      FullPagedNativeError.None
  assert other.readContext(config.limits.work).value.bytes == before
  assert other.close == FileError.None
  assert writer.reclaim(wrongPolicy, writer.selected.value).error ==
      FullPagedNativeError.InvalidCandidate
  let busy = writer.reclaim(oldReceipt, writer.selected.value)
  assert busy.error == FullPagedNativeError.FileFailure and busy.fileError == FileError.Busy
  assert reader.close == FileError.None
  assert writer.reclaim(oldReceipt, writer.selected.value).error == FullPagedNativeError.None
  assert writer.close == FileError.None
  assert newest.close == FileError.None
  assert retained.bytes == before and uint64(retained.manifest.epoch) == 1
  assert captured.bytes == after and uint64(captured.manifest.epoch) == 2
proc refusals(source: FullPagedFixture) =
  ## Format presence, context policy and exact provided bytes refuse before any native bootstrap namespace is acquired.
  let context = body(33)
  let config = configuration(source, 33)
  var writer = default(FullPagedWriter)
  let missing = initializeFullPagedWriter(writer, path("missing"), config, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes)
  assert missing.error == FullPagedNativeError.GraphFailure
  assert missing.graphError == FullPagedStreamError.UnsupportedPolicy and not writer.opened
  var short = config
  short.limits.contextBytes = ByteLimit(32)
  let excess = initializeFullPagedWriter(writer, path("excess"), short, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes, context)
  assert excess.error == FullPagedNativeError.GraphFailure and excess.graphError ==
      FullPagedStreamError.LimitExceeded
  assert not writer.opened
  let unexpected = initializeFullPagedWriter(writer, path("unexpected"), source.config,
      source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes, context)
  assert unexpected.error == FullPagedNativeError.GraphFailure
  assert unexpected.graphError == FullPagedStreamError.UnsupportedPolicy and not writer.opened
  initialize(writer, path("missing"), source, config, context)
  assert writer.close == FileError.None
  var reader = default(FullPagedReader)
  assert openFullPagedReader(reader, path("missing"), source.config).error ==
      FullPagedNativeError.CodecFailure
  assert not reader.opened
  assert openFullPagedReader(reader, path("missing"), config).error == FullPagedNativeError.None
  resetIo()
  var zero = config.limits.work
  zero.ioCalls = ElementLimit(0)
  let refused = reader.readContext(zero)
  assert refused.error == FullPagedNativeError.GraphFailure
  assert refused.graphError == FullPagedStreamError.LimitExceeded and ioCalls(readIo) == 0
  assert reader.close == FileError.None
  assert reader.readContext(config.limits.work).error == FullPagedNativeError.Uninitialized
proc nativeFailures(source: FullPagedFixture) =
  ## Every observed context source read failure preserves whole-result refusal and requires fresh native reopen.
  let directory = path("read-failures")
  let context = body(4097)
  let config = configuration(source)
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  initialize(writer, directory, source, config, context)
  assert writer.close == FileError.None
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  resetIo()
  assert reader.readContext(config.limits.work).value.bytes == context
  let reads = ioCalls(readIo)
  assert reads > 0 and ioCalls(writeIo) == 0
  for skip in 0..<int(reads):
    # Native test instrumentation refuses one actual SDK call at each observed boundary.
    resetIo()
    armIo(readIo, cint(skip), 1, failedIo)
    let refused = reader.readContext(config.limits.work)
    assert refused.error == FullPagedNativeError.GraphFailure and refused.graphError ==
        FullPagedStreamError.IOFailure
    assert pendingIo() == 0
    resetIo()
    assert reader.close == FileError.None
    assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  assert reader.close == FileError.None
proc replay(source: FullPagedFixture) =
  ## Complete candidate replay binds opaque context bytes even when complete JAM roots/counts remain unchanged.
  let directory = path("replay")
  let initial = body(33, 7)
  let target = body(4097, 9)
  let config = configuration(source)
  let wanted = expected(source, target, 2, 1, config.limits.dataset)
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  initialize(writer, directory, source, config, initial)
  let current = read(directory & "/CURRENT")
  let selected = writer.selected.value
  assert prepareFullPagedReplacement(writer, candidate, source.header.root, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes,
    target).error == FullPagedNativeError.None
  resetIo()
  armIo(renameIo, 0, 1, failedIo)
  assert writer.publish(candidate).error != FullPagedNativeError.None
  assert pendingIo() == 0
  resetIo()
  assert candidate.close == FileError.None
  assert writer.close == FileError.None
  assert read(directory & "/CURRENT") == current
  assert openFullPagedWriter(writer, directory, config).error == FullPagedNativeError.None
  var wrong = clone(target)
  wrong[4096] = wrong[4096] xor 1
  resetIo()
  let refused = prepareFullPagedCleanup(writer, candidate, selected, wanted.header,
    source.records.producer, wrong)
  assert refused.error != FullPagedNativeError.None
  assert ioCalls(unlinkIo) == 0 and read(directory & "/CURRENT") == current
  assert not candidate.opened
  assert prepareFullPagedCleanup(writer, candidate, selected, wanted.header,
    source.records.producer, target).error == FullPagedNativeError.None
  assert writer.discardFullPagedCandidate(candidate, selected).error == FullPagedNativeError.None
  assert read(directory & "/CURRENT") == current
  assert prepareFullPagedReplacement(writer, candidate, source.header.root, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes,
    target).error == FullPagedNativeError.None
  assert writer.publish(candidate).error == FullPagedNativeError.None
  assert writer.readContext(config.limits.work).value.bytes == target
  assert writer.close == FileError.None
proc corruptions(source: FullPagedFixture) =
  ## Resealed noncanonical padding is still malformed; unresealed opaque context corruption fails page authentication.
  let context = body(33)
  let config = configuration(source)
  let oracle = expected(source, context, 1, 0, config.limits.dataset)
  for kind in 0..<3:
    # Each native namespace starts from independently reproduced valid bytes and one focused mutation.
    let directory = path("corrupt-" & $kind)
    var writer = default(FullPagedWriter)
    initialize(writer, directory, source, config, context)
    assert writer.close == FileError.None
    var bytes = clone(oracle.io.bytes)
    var manifest = oracle.manifest
    if kind == 0:
      bytes[int(uint64(oracle.header.geometry.contextOffset))+1] = 99 # Leave the captured page root unchanged.
    else:
      # Recompute the complete local tree to prove structural refusal does not merely depend on an invalid checksum.
      let position = if kind == 1:
        uint64(oracle.header.geometry.contextOffset)+uint64(context.len)
      else: uint64(oracle.header.geometry.payloadOffset)+oracle.header.geometry.payloadBytes
      bytes[int(position)] = 1
      var data = newSeq[byte](int(uint64(oracle.header.geometry.treeOffset)))
      for index in 0..<data.len: data[index] = bytes[index] # Copy exact mutated physical data pages only.
      let root = tree(data, int(oracle.header.geometry.dataPages), 0, int(
          oracle.header.geometry.treeLeaves))
      bytes = data
      manifest = encodeFullPagedManifest(oracle.header, FullPagedDigest(root)).value
    write(directory & "/" & epochName(ManagedEpoch(1)).value, bytes)
    write(directory & "/CURRENT", manifest.bytes.value)
    let selected = read(directory & "/CURRENT")
    resetIo()
    var reader = default(FullPagedReader)
    let refused = openFullPagedReader(reader, directory, config)
    assert refused.error == FullPagedNativeError.GraphFailure
    assert refused.graphError == FullPagedStreamError.CodecFailure and not reader.opened
    if kind == 0:
      assert refused.graphCodecError == FullPagedError.ChecksumMismatch # Data mutation is cryptographic corruption.
    else:
      assert refused.graphCodecError == FullPagedError.InvalidFormat # A valid local tree cannot authorize hidden padding.
    assert ioCalls(unlinkIo) == 0 and ioCalls(renameIo) == 0
    assert read(directory & "/CURRENT") == selected
    assert read(directory & "/" & epochName(ManagedEpoch(1)).value) == text(bytes)
proc writeFailures(source: FullPagedFixture) =
  ## Every observed candidate write refuses without moving CURRENT; complete fresh readers still restore the old context.
  let initial = body(33, 7)
  let target = body(4097, 9)
  let config = configuration(source)
  var writer = default(FullPagedWriter)
  var candidate = default(FullPagedCandidate)
  initialize(writer, path("write-baseline"), source, config, initial)
  resetIo()
  assert prepareFullPagedReplacement(writer, candidate, source.header.root, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes,
    target).error == FullPagedNativeError.None
  let writes = ioCalls(writeIo)
  assert writes > 0
  assert candidate.close == FileError.None
  assert writer.close == FileError.None
  for skip in 0..<int(writes):
    # Fault every actual SDK write, including context pages, tree digests and admission's private graph scratch.
    resetIo()
    let directory = path("write-failure-" & $skip)
    initialize(writer, directory, source, config, initial)
    let selected = read(directory & "/CURRENT")
    resetIo()
    armIo(writeIo, cint(skip), 1, failedIo)
    assert prepareFullPagedReplacement(writer, candidate, source.header.root, source.roots,
      source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes,
      target).error != FullPagedNativeError.None
    assert pendingIo() == 0
    resetIo()
    if candidate.opened: assert candidate.close ==
        FileError.None # Forensic prefixes keep no escaped descriptor owner.
    assert writer.close == FileError.None
    assert read(directory & "/CURRENT") == selected
    var reader = default(FullPagedReader)
    assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
    assert reader.readContext(config.limits.work).value.bytes == initial
    assert reader.close == FileError.None
proc bootstrap(source: FullPagedFixture) =
  ## Explicit V2 bootstrap replay reproduces context before deleting any incomplete initial epoch prefix.
  let directory = path("bootstrap")
  let context = body(4097)
  let config = configuration(source)
  var writer = default(FullPagedWriter)
  resetIo()
  armIo(writeIo, 0, 1, failedIo)
  assert initializeFullPagedWriter(writer, directory, config, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes,
    context).error != FullPagedNativeError.None
  assert pendingIo() == 0
  resetIo()
  if writer.opened: assert writer.close == FileError.None # Failed acquired bootstrap leases remain caller-owned.
  assert resumeFullPagedInitialization(writer, directory, config, source.roots,
    source.records.producer, source.header.geometry.entries, source.header.geometry.payloadBytes,
    context).error == FullPagedNativeError.None
  assert writer.readContext(config.limits.work).value.bytes == context
  let oracle = expected(source, context, 1, 0, config.limits.dataset)
  assert read(directory & "/CURRENT") == text(oracle.manifest.bytes.value)
  assert read(directory & "/" & epochName(ManagedEpoch(1)).value) == text(oracle.io.bytes)
  assert writer.close == FileError.None
proc cycle(reader: var FullPagedReader, directory: string, config: FullPagedNativeConfig,
    context: seq[byte], lateRead: cint) =
  ## Success copies and a late failed private prefix retire around a genuine poisoned-reader close/reopen.
  let captured = reader.readContext(config.limits.work).value
  assert captured.bytes == context
  var bytes = captured.bytes
  bytes[0] = 99
  assert captured.bytes == context
  resetIo()
  armIo(readIo, lateRead, 1, failedIo)
  let refused = reader.readContext(config.limits.work)
  assert refused.error == FullPagedNativeError.GraphFailure and refused.graphError ==
      FullPagedStreamError.IOFailure
  assert pendingIo() == 0
  resetIo()
  assert reader.close == FileError.None
  assert captured.bytes == context # Captured context owns no foreign file or pin alias.
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
proc main() =
  ## Native IO and independent roots qualify atomic opaque context without application trust shortcuts.
  let source = sample(7)
  let history = historySample(7, 9)
  lowLevel(source)
  normal(source, history)
  refusals(source)
  nativeFailures(source)
  corruptions(source)
  writeFailures(source)
  bootstrap(source)
  replay(source)
  let config = configuration(source)
  let context = body(4097)
  let directory = path("cycles")
  var writer = default(FullPagedWriter)
  var reader = default(FullPagedReader)
  initialize(writer, directory, source, config, context)
  assert writer.close == FileError.None
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  resetIo()
  assert reader.readContext(config.limits.work).value.bytes == context
  let calls = ioCalls(readIo)
  assert calls > 0 and calls <= uint64(high(cint))
  let lateRead = cint(calls-1)
  cycle(reader, directory, config, context, lateRead)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Each cycle also releases a partially copied failed context before a fresh native reopen.
    cycle(reader, directory, config, context, lateRead)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_context", 1000, before, after)
  assert reader.close == FileError.None
  echo "storage full paged context PASS"
main()
