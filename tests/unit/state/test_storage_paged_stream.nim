# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent byte/proof oracles exercise streamed construction, strict admission and bounded authenticated search.
# @@Verification={"arc":"storage_paged_stream_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/storage_paged_reference
import ../../../src/storage/paged_stream as storage_paged_stream
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Independent primitive failure controls leave production IO/proof algorithms intact.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse each actual hash invocation in an otherwise successful operation.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Distinguish structural/resource preflight from attempted primitive work.

type
  Memory = ref object ## Resident test transport only; no production API retains this or its callback closures.
    bytes: seq[byte]
    overlay: seq[byte]
    overlayPage: int
    reads, writes, extents: int
    failRead, failWrite, failExtent, growExtent: int
    shortWrite, changeKnowledge: bool
  Producer = ref object ## Caller-owned test fixture supports deterministic replay changes and explicit failure/end cases.
    records: seq[LightStateProof]
    calls: int
    mode: string
  Fixture = object ## Independent full-map state/proof evidence includes presence, empty presence and retained absence.
    root: StateRoot
    records: seq[LightStateProof]
proc copy(input: seq[byte]): seq[byte] =
  ## Explicitly detach mutable test sources so one corruption cannot change a reference fixture.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index]
func key(first: byte): StateKey =
  ## Sorted fixture identities differ in their most significant serialized octet.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
func workLimits(): PagedWorkLimits =
  ## Generous finite controls permit exact observed-budget replay without hidden unlimited sentinels.
  PagedWorkLimits(ioCalls: ElementLimit(1000000), producerCalls: ElementLimit(1000000),
    pageHashes: ElementLimit(1000000), proofs: ElementLimit(1000000), nodes: ElementLimit(1000000),
    readBytes: ByteLimit(100000000), writeBytes: ByteLimit(100000000), valueBytes: ByteLimit(100000000))
func policy(cache = 1): PagedStreamLimits =
  ## Dataset totals, one-record payloads and aggregate work are independent explicit policies.
  PagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(10000), bytes: ByteLimit(10000000)),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(10000)),
    workingBytes: ByteLimit(100000), cachePages: ElementLimit(cache), work: workLimits())
proc input(memory: Memory): PagedInput =
  ## Each callback is synchronous and captures a test owner without forming an ownership cycle.
  proc read(offset: PagedOffset, output: var openArray[byte]): bool {.closure.} =
    ## Exact reads expose every observed boundary; false may follow a partial copy, which grants no admission.
    inc memory.reads
    let start = uint64(offset)
    if start > uint64(memory.bytes.len) or uint64(output.len) > uint64(
        memory.bytes.len)-start: return false
    for index in 0..<output.len: output[index] = memory.bytes[int(start)+index]
    if memory.overlay.len > 0 and start == uint64(memory.overlayPage*4096) and output.len == 4096:
      # A hostile source substitutes an earlier valid proof page against a different captured digest root.
      for index in 0..<4096: output[index] = memory.overlay[memory.overlayPage*4096+index]
    memory.reads != memory.failRead
  proc extent(output: var uint64): bool {.closure.} =
    ## EOF changes at the final check must defeat both successful lookups and UnknownKey.
    inc memory.extents
    if memory.extents == memory.growExtent: memory.bytes.add(0)
    output = uint64(memory.bytes.len)
    memory.extents != memory.failExtent
  PagedInput(read: read, extent: extent)
proc output(memory: Memory): PagedOutput =
  ## Appending is the only available mutation; short failures preserve the exact emitted canonical prefix.
  proc append(bytes: openArray[byte]): bool {.closure.} =
    ## A simulated short append never claims success, unlike positive complete writes.
    inc memory.writes
    if memory.writes == memory.failWrite:
      if memory.shortWrite:
        for index in 0..<bytes.len div 2: memory.bytes.add(bytes[index])
      return false
    let start = memory.bytes.len
    for octet in bytes: memory.bytes.add(octet)
    if memory.changeKnowledge and (start == 4096 or start == 8192):
      # Simulate an external mutation to a different valid same-root knowledge set after a completed append.
      memory.bytes[start] = 1
    true
  PagedOutput(source: memory.input, append: append)
proc producer(source: Producer): PagedProducer =
  ## Caller fixtures are resident only in tests; production consumes one bounded item at a time.
  proc next(pass: int, ordinal: uint64, record: var LightStateProof): PagedProducerStep {.closure.} =
    ## End/failure/change controls do not reuse output from a previous ordinal.
    inc source.calls
    if source.mode == "failure" and pass == 1 and ordinal == 1: return PagedProducerStep.Failed
    if source.mode == "early" and ordinal == 1: return PagedProducerStep.End
    if ordinal >= uint64(source.records.len):
      if source.mode == "extra":
        record = source.records[0]
        return PagedProducerStep.Item
      return PagedProducerStep.End
    record = source.records[int(ordinal)]
    if source.mode == "changed" and pass == 1 and ordinal == 0: record.key = key(1)
    PagedProducerStep.Item
  next
proc selected(reference: PagedReference, root: StateRoot): PagedManifest =
  ## Manifest decoding starts from independent oracle transport and independently expected chain/root.
  decodePagedManifest(reference.manifest, default(StorageChainId), root, policy().dataset,
      ByteLimit(193)).value
proc fixture(): Fixture =
  ## The independent complete-map calculator anchors production-generated query proof transport.
  let entries = @[StateEntry(key: key(0), value: newSeq[byte](4097)),
    StateEntry(key: key(64), value: @[]), StateEntry(key: key(128), value: @[1'u8, 2, 3])]
  let limits = StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(10000),
    totalValueBytes: ByteLimit(20000), nodes: TrieNodeLimit(1000))
  let root = stateTrieRoot(entries, limits).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  result = Fixture(root: root, records: @[])
  for first in [0'u8, 64, 128, 255]:
    result.records.add(LightStateProof(key: key(first), proof: trie.prove(key(first), policy().proof).value))
proc emptyRecords(): seq[LightStateProof] =
  ## Independent empty-root absence evidence remains distinct from any query not retained in the index.
  @[LightStateProof(key: key(0), proof: StateProof()), LightStateProof(key: key(128),
      proof: StateProof())]
proc build(source: Producer, memory: Memory, root: StateRoot,
    limits: PagedStreamLimits): PagedStreamResult[CheckedPagedArtifact] =
  ## Test-size count/extent declaration is independent of the builder's proof sizing/encoding code.
  var extent = 0'u64
  for index in 0..<source.records.len:
    let record = source.records[index]
    extent += 41+uint64(record.proof.nodes.len)*64+uint64(record.proof.value.len)
  let header = initPagedHeader(default(StorageChainId), root, ManagedEpoch(1), LightDeltaSequence(0),
    uint64(source.records.len), extent, limits.dataset).value
  buildPagedArtifact(memory.output, source.producer, header, limits)
proc matches(left, right: VerifiedStateLookup) =
  ## Existing verified-cache results independently constrain new source-backed query semantics.
  assert left.kind == right.kind
  assert array[32, byte](left.root) == array[32, byte](right.root)
  assert array[31, byte](left.key) == array[31, byte](right.key)
  if left.kind == StateLookupKind.Present: assert left.bytes == right.bytes
proc success(data: Fixture) =
  ## Both cache modes produce exact independent bytes and agree with the existing resident cache/image contracts.
  let reference = pagedReference(default(StorageChainId), data.root, data.records)
  let residentPolicy = LightCacheLimits(items: ElementLimit(100), writes: ElementLimit(100),
    valueBytes: ByteLimit(20000), proof: policy().proof)
  let cache = newLightStateCache(data.root, data.records, residentPolicy).value
  let image = prepareLightSnapshot(default(StorageChainId), data.root, data.records,
    LightSnapshotLimits(cache: residentPolicy, bytes: ByteLimit(100000))).value
  assert image.initialized
  for capacity in [0, 1]:
    # Every operation uses fresh bounded scratch; neither metadata nor returned lookup retains IO callbacks.
    let memory = Memory(bytes: @[])
    let source = Producer(records: data.records)
    let built = build(source, memory, data.root, policy(capacity)).value
    assert memory.bytes == reference.bytes
    assert built.manifest.bytes == reference.manifest
    assert built.counts.producerCalls == uint64(2*(data.records.len+1))
    assert built.counts.proofs == uint64(3*data.records.len)
    assert built.counts.writeBytes == uint64(reference.bytes.len)
    assert built.counts.ioCalls == uint64(memory.reads+memory.writes+memory.extents)
    assert uint64(built.header.geometry.entries) == uint64(data.records.len)
    let admitted = validatePagedArtifact(memory.input, selected(reference, data.root), policy(
        capacity)).value
    assert admitted.counts.proofs == uint64(data.records.len)
    assert admitted.counts.writeBytes == 0 and admitted.counts.producerCalls == 0
    for first in [0'u8, 64, 128, 255]:
      let found = lookupPaged(admitted, memory.input, key(first), workLimits()).value
      matches(found.verified, cache.lookup(key(first)).value)
      matches(found.verified, image.cache.lookup(key(first)).value)
      assert found.counts.proofs == 1
    assert lookupPaged(admitted, memory.input, key(192), workLimits()).error ==
        PagedStreamError.UnknownKey
    assert cache.lookup(key(192)).error == LightCacheError.UnknownKey
    let owned = lookupPaged(admitted, memory.input, key(0), workLimits()).value.verified
    let absent = lookupPaged(admitted, memory.input, key(255), workLimits()).value.verified
    memory.bytes.setLen(0)
    assert owned.bytes == newSeq[byte](4097)
    assert absent.kind == StateLookupKind.Absent
    var detached = owned.bytes
    detached[0] = 99
    assert owned.bytes[0] == 0
proc emptyAndReplay() =
  ## Empty roots keep local UnknownKey distinct from retained authenticated absence; builds are never implicit conversions.
  for records in [newSeq[LightStateProof](0), emptyRecords()]:
    let reference = pagedReference(default(StorageChainId), default(StateRoot), records)
    let memory = Memory(bytes: @[])
    let built = build(Producer(records: records), memory, default(StateRoot), policy()).value
    assert memory.bytes == reference.bytes and built.manifest.bytes == reference.manifest
    assert lookupPaged(built, memory.input, key(64), workLimits()).error ==
        PagedStreamError.UnknownKey
    if records.len > 0:
      assert lookupPaged(built, memory.input, key(128), workLimits()).value.verified.kind ==
          StateLookupKind.Absent
    else:
      assert lookupPaged(built, memory.input, key(0), workLimits()).error ==
          PagedStreamError.UnknownKey
    let before = copy(memory.bytes)
    let writes = memory.writes
    assert build(Producer(records: records), memory, default(StateRoot), policy()).error ==
        PagedStreamError.ChangedInput
    assert memory.bytes == before and memory.writes == writes
  let mutated = Memory(bytes: @[], changeKnowledge: true)
  assert build(Producer(records: emptyRecords()), mutated, default(StateRoot), policy()).error ==
      PagedStreamError.ChangedInput
  for mode in ["changed", "early", "extra", "failure"]:
    # A different valid empty-root knowledge stream still cannot reuse the first pass's index.
    let memory = Memory(bytes: @[])
    let reason = if mode == "changed": PagedStreamError.ChangedInput
      elif mode == "failure": PagedStreamError.ProducerFailure
      else: PagedStreamError.InvalidFormat
    assert build(Producer(records: emptyRecords(), mode: mode), memory, default(StateRoot), policy()).error == reason
    assert memory.bytes.len >= 4096
proc copyRecords(input: seq[LightStateProof]): seq[LightStateProof] =
  ## Deep test detachment prevents false-proof mutations from changing later positive-control evidence.
  result = newSeq[LightStateProof](input.len)
  for index in 0..<input.len:
    var nodes = newSeq[EncodedStateNode](input[index].proof.nodes.len)
    for slot in 0..<nodes.len: nodes[slot] = input[index].proof.nodes[slot]
    result[index] = LightStateProof(key: input[index].key,
      proof: StateProof(nodes: nodes, value: copy(input[index].proof.value)))
proc strictCorruption(data: Fixture) =
  ## Correctly recomputed file hashes never authenticate false query proofs, bad index shape or noncanonical padding.
  let absent = emptyRecords()
  let reference = pagedReference(default(StorageChainId), default(StateRoot), absent)
  let selection = selected(reference, default(StateRoot))
  for size in 0..<reference.bytes.len:
    # All proper artifact prefixes fail actual EOF preflight without reading, hashing or exposing a prefix owner.
    var bytes = newSeq[byte](size)
    for index in 0..<size: bytes[index] = reference.bytes[index]
    let memory = Memory(bytes: bytes)
    resetHash(0)
    assert validatePagedArtifact(memory.input, selection, policy()).error ==
        PagedStreamError.ChangedInput
    assert memory.reads == 0 and hashCalls() == 0
  var extra = copy(reference.bytes)
  extra.add(0)
  assert validatePagedArtifact(Memory(bytes: extra).input, selection, policy()).error ==
      PagedStreamError.ChangedInput
  for offset in [120, 4096+47, 4096+128, 8192+82, 12287]:
    # Rehashed header/index padding/reserved and payload padding errors remain strict format refusals.
    var changed = reference
    changed.bytes = copy(reference.bytes)
    changed.bytes[offset] = 1
    changed.recommit()
    let result = validatePagedArtifact(Memory(bytes: changed.bytes).input, selected(changed,
        default(StateRoot)), policy())
    assert result.error == PagedStreamError.InvalidFormat
  for mode in ["duplicate", "gap", "short", "alias", "count"]:
    var changed = reference
    changed.bytes = copy(reference.bytes)
    case mode
    of "duplicate":
      changed.bytes[4096+64] = 0
      changed.bytes[8192+41] = 0
    of "gap":
      put(changed.bytes, 112, 83)
      put(changed.bytes, 4096+64+31, 42)
    of "short": put(changed.bytes, 4096+39, 40)
    of "alias": put(changed.bytes, 4096+64+31, 0)
    else: put(changed.bytes, 104, 1)
    changed.recommit()
    assert validatePagedArtifact(Memory(bytes: changed.bytes).input, selected(changed, default(
        StateRoot)), policy()).error == PagedStreamError.InvalidFormat
  for slot in 0..<7:
    # Every stored postorder slot, including the final root that lookup paths need not read, is checked.
    var bytes = copy(reference.bytes)
    bytes[reference.pages*4096+slot*32] = bytes[reference.pages*4096+slot*32] xor 1
    assert validatePagedArtifact(Memory(bytes: bytes).input, selection, policy()).error ==
        PagedStreamError.ChecksumMismatch
  var falseProofs = copyRecords(data.records)
  falseProofs[0].proof.value[0] = 99
  let falseReference = pagedReference(default(StorageChainId), data.root, falseProofs)
  let falseSelection = selected(falseReference, data.root)
  let refused = validatePagedArtifact(Memory(bytes: falseReference.bytes).input, falseSelection,
      policy())
  assert refused.error == PagedStreamError.ProofFailure and refused.proofError ==
      StateProofError.ValueMismatch
  let good = pagedReference(default(StorageChainId), data.root, data.records)
  let payloadPage = 1+(64*data.records.len+4095) div 4096
  let switched = Memory(bytes: falseReference.bytes, overlay: good.bytes, overlayPage: payloadPage)
  assert validatePagedArtifact(switched.input, falseSelection, policy()).error ==
      PagedStreamError.ChecksumMismatch
  var noNodes = copyRecords(data.records)
  noNodes[0].proof.nodes = @[]
  let incomplete = pagedReference(default(StorageChainId), data.root, noNodes)
  let failed = validatePagedArtifact(Memory(bytes: incomplete.bytes).input, selected(incomplete,
      data.root), policy())
  assert failed.error == PagedStreamError.ProofFailure and failed.proofError ==
      StateProofError.IncompleteProof
proc lookupCorruption(data: Fixture) =
  ## Captured digest roots survive transport replacement; local cache misses never turn read faults into UnknownKey.
  let reference = pagedReference(default(StorageChainId), data.root, data.records)
  let selected = selected(reference, data.root)
  let checked = validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, policy()).value
  for offset in [0, 120, 4096, 8192, reference.pages*4096+32]:
    var bytes = copy(reference.bytes)
    bytes[offset] = bytes[offset] xor 1
    let reason = lookupPaged(checked, Memory(bytes: bytes).input, key(0), workLimits()).error
    assert reason == PagedStreamError.ChecksumMismatch
  let unknownSource = Memory(bytes: reference.bytes, growExtent: 2)
  assert lookupPaged(checked, unknownSource.input, key(192), workLimits()).error ==
      PagedStreamError.ChangedInput
  let foundSource = Memory(bytes: reference.bytes, growExtent: 2)
  assert lookupPaged(checked, foundSource.input, key(0), workLimits()).error ==
      PagedStreamError.ChangedInput
  for query in [key(0), key(192)]:
    let source = Memory(bytes: reference.bytes)
    let control = lookupPaged(checked, source.input, query, workLimits())
    assert control.error == PagedStreamError.None or control.error == PagedStreamError.UnknownKey
    for call in 1..source.reads:
      let bad = Memory(bytes: reference.bytes, failRead: call)
      assert lookupPaged(checked, bad.input, query, workLimits()).error ==
          PagedStreamError.IOFailure
    for call in 1..2:
      let bad = Memory(bytes: reference.bytes, failExtent: call)
      assert lookupPaged(checked, bad.input, query, workLimits()).error ==
          PagedStreamError.IOFailure
func budget(counts: PagedStreamCounts): PagedWorkLimits =
  ## Replay successful observed work with exact ceilings rather than implementation-derived guesses.
  PagedWorkLimits(ioCalls: ElementLimit(counts.ioCalls), producerCalls: ElementLimit(
      counts.producerCalls),
    pageHashes: ElementLimit(counts.pageHashes), proofs: ElementLimit(counts.proofs),
        nodes: ElementLimit(counts.nodes),
    readBytes: ByteLimit(counts.readBytes), writeBytes: ByteLimit(counts.writeBytes),
        valueBytes: ByteLimit(counts.valueBytes))
proc reduce(limits: var PagedWorkLimits, field: int): bool =
  ## Tighten exactly one positive observed channel; absent work channels remain explicit zero allowances.
  result = true
  case field
  of 0:
    if uint64(limits.ioCalls) > 0: limits.ioCalls = ElementLimit(uint64(limits.ioCalls)-1)
    else: result = false
  of 1:
    if uint64(limits.producerCalls) > 0: limits.producerCalls = ElementLimit(uint64(
        limits.producerCalls)-1)
    else: result = false
  of 2:
    if uint64(limits.pageHashes) > 0: limits.pageHashes = ElementLimit(uint64(limits.pageHashes)-1)
    else: result = false
  of 3:
    if uint64(limits.proofs) > 0: limits.proofs = ElementLimit(uint64(limits.proofs)-1)
    else: result = false
  of 4:
    if uint64(limits.nodes) > 0: limits.nodes = ElementLimit(uint64(limits.nodes)-1)
    else: result = false
  of 5:
    if uint64(limits.readBytes) > 0: limits.readBytes = ByteLimit(uint64(limits.readBytes)-1)
    else: result = false
  of 6:
    if uint64(limits.writeBytes) > 0: limits.writeBytes = ByteLimit(uint64(limits.writeBytes)-1)
    else: result = false
  else:
    if uint64(limits.valueBytes) > 0: limits.valueBytes = ByteLimit(uint64(limits.valueBytes)-1)
    else: result = false
proc budgets(data: Fixture) =
  ## Each operation succeeds at every exact observed budget and refuses one short in each positive channel.
  let reference = pagedReference(default(StorageChainId), data.root, data.records)
  let selected = selected(reference, data.root)
  let built = build(Producer(records: data.records), Memory(bytes: @[]), data.root, policy()).value
  let admitted = validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, policy()).value
  let found = lookupPaged(admitted, Memory(bytes: reference.bytes).input, key(0), workLimits()).value
  for operation in 0..<3:
    let counts = if operation == 0: built.counts elif operation ==
        1: admitted.counts else: found.counts
    var limits = policy()
    limits.work = budget(counts)
    if operation == 0:
      assert build(Producer(records: data.records), Memory(bytes: @[]), data.root, limits).error ==
          PagedStreamError.None
    elif operation == 1:
      assert validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, limits).error ==
          PagedStreamError.None
    else:
      assert lookupPaged(admitted, Memory(bytes: reference.bytes).input, key(0),
          limits.work).error == PagedStreamError.None
    for channel in 0..<8:
      # Only the single changed ceiling differs from a passing exact-budget positive control.
      var short = limits
      if reduce(short.work, channel):
        let reason = if operation == 0: build(Producer(records: data.records), Memory(bytes: @[]),
            data.root, short).error
          elif operation == 1: validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, short).error
          else: lookupPaged(admitted, Memory(bytes: reference.bytes).input, key(0),
              short.work).error
        assert reason == PagedStreamError.LimitExceeded
  var limits = policy()
  limits.workingBytes = ByteLimit(PagedStreamFixedBytes+40)
  let memory = Memory(bytes: @[])
  let source = Producer(records: data.records)
  resetHash(0)
  assert build(source, memory, data.root, limits).error == PagedStreamError.LimitExceeded
  assert memory.writes == 0 and memory.extents == 0 and source.calls == 0 and hashCalls() == 0
  limits = policy()
  limits.dataset.bytes = ByteLimit(uint64(reference.bytes.len)-1)
  let limited = Memory(bytes: reference.bytes)
  assert validatePagedArtifact(limited.input, selected, limits).error ==
      PagedStreamError.LimitExceeded
  assert limited.extents == 0 and limited.reads == 0
  let first = data.records[0].proof
  let required = PagedStreamFixedBytes+41+2*uint64(first.nodes.len)*64+2*uint64(first.value.len)
  limits = policy()
  limits.workingBytes = ByteLimit(required)
  assert build(Producer(records: data.records), Memory(bytes: @[]), data.root, limits).error ==
      PagedStreamError.None
  limits.workingBytes = ByteLimit(required-1)
  resetHash(1)
  assert build(Producer(records: data.records), Memory(bytes: @[]), data.root, limits).error ==
      PagedStreamError.LimitExceeded
  assert hashCalls() == 0
  resetHash(0)
  limits = policy()
  limits.cachePages = ElementLimit(2)
  assert validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, limits).error ==
      PagedStreamError.UnsupportedPolicy
  limits = policy()
  limits.proof.valueBytes = ByteLimit(4096)
  assert validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, limits).error ==
      PagedStreamError.LimitExceeded
  limits = policy()
  limits.dataset.entries = ElementLimit(3)
  assert validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, limits).error ==
      PagedStreamError.LimitExceeded
  let missing = default(CheckedPagedArtifact)
  assert not missing.initialized
  assert lookupPaged(missing, default(PagedInput), key(0), workLimits()).error ==
      PagedStreamError.Uninitialized
  assert validatePagedArtifact(default(PagedInput), selected, policy()).error ==
      PagedStreamError.Uninitialized
  let header = built.header
  assert buildPagedArtifact(default(PagedOutput), source.producer, header, policy()).error ==
      PagedStreamError.Uninitialized
  var noProducer: nil PagedProducer = nil
  assert buildPagedArtifact(memory.output, noProducer, header, policy()).error ==
      PagedStreamError.Uninitialized
proc prefixOf(input, complete: seq[byte]): bool =
  ## Failure tests preserve every existing emitted byte rather than silently truncate or repair candidates.
  if input.len > complete.len: return false
  for index in 0..<input.len:
    if input[index] != complete[index]: return false
  true
proc ioFaults(data: Fixture) =
  ## Every actual append/read/EOF boundary has a passing control and a typed-failure witness.
  let reference = pagedReference(default(StorageChainId), data.root, data.records)
  let selected = selected(reference, data.root)
  let control = Memory(bytes: @[])
  discard build(Producer(records: data.records), control, data.root, policy()).value
  for short in [false, true]:
    for call in 1..control.writes:
      # Short append uncertainty preserves an exact canonical prefix and cannot return a completed candidate.
      let memory = Memory(bytes: @[], failWrite: call, shortWrite: short)
      assert build(Producer(records: data.records), memory, data.root, policy()).error ==
          PagedStreamError.IOFailure
      assert prefixOf(memory.bytes, reference.bytes)
      assert memory.writes == call
  for call in 1..control.reads:
    let memory = Memory(bytes: @[], failRead: call)
    assert build(Producer(records: data.records), memory, data.root, policy()).error ==
        PagedStreamError.IOFailure
    assert prefixOf(memory.bytes, reference.bytes)
    assert memory.reads == call
  for call in 1..control.extents:
    let memory = Memory(bytes: @[], failExtent: call)
    assert build(Producer(records: data.records), memory, data.root, policy()).error ==
        PagedStreamError.IOFailure
  let readControl = Memory(bytes: reference.bytes)
  discard validatePagedArtifact(readControl.input, selected, policy()).value
  for call in 1..readControl.reads:
    let memory = Memory(bytes: reference.bytes, failRead: call)
    assert validatePagedArtifact(memory.input, selected, policy()).error ==
        PagedStreamError.IOFailure
    assert memory.reads == call and memory.bytes == reference.bytes
  for call in 1..readControl.extents:
    let memory = Memory(bytes: reference.bytes, failExtent: call)
    assert validatePagedArtifact(memory.input, selected, policy()).error ==
        PagedStreamError.IOFailure
  assert validatePagedArtifact(Memory(bytes: copy(reference.bytes), growExtent: 2).input, selected,
      policy()).error == PagedStreamError.ChangedInput
proc providerFaults(data: Fixture) =
  ## Provider refusal at every observed hash stage never grants a proof, UnknownKey or completed artifact.
  let reference = pagedReference(default(StorageChainId), data.root, data.records)
  let selected = selected(reference, data.root)
  let admitted = validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, policy()).value
  for operation in 0..<3:
    resetHash(0)
    if operation == 0:
      discard build(Producer(records: data.records), Memory(bytes: @[]), data.root, policy()).value
    elif operation == 1:
      discard validatePagedArtifact(Memory(bytes: reference.bytes).input, selected, policy()).value
    else:
      discard lookupPaged(admitted, Memory(bytes: reference.bytes).input, key(0), workLimits()).value
    let count = hashCalls()
    assert count > 0
    for successful in 0..<int(count):
      # Each refusal has exactly the intended number of successful primitive calls before it.
      failAfter(cint(successful))
      let reason = if operation == 0: build(Producer(records: data.records), Memory(bytes: @[]),
          data.root, policy()).error
        elif operation == 1: validatePagedArtifact(Memory(bytes: reference.bytes).input, selected,
            policy()).error
        else: lookupPaged(admitted, Memory(bytes: reference.bytes).input, key(0), workLimits()).error
      assert reason == PagedStreamError.BackendFailure
      assert hashCalls() == cint(successful+1)
    resetHash(0)
proc deepestProof() =
  ## Two keys differing only at bit 247 force all 248 branches plus one terminal leaf through the streaming path.
  var other = default(array[31, byte])
  other[30] = 1
  let entries = @[StateEntry(key: default(StateKey), value: @[1'u8]),
    StateEntry(key: StateKey(other), value: @[2'u8])]
  let limits = StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1000))
  let root = stateTrieRoot(entries, limits).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits)).value
  let proof = trie.prove(default(StateKey), policy().proof).value
  assert proof.nodes.len == 249
  let records = @[LightStateProof(key: default(StateKey), proof: proof)]
  let reference = pagedReference(default(StorageChainId), root, records)
  for capacity in [0, 1]:
    let memory = Memory(bytes: @[])
    let built = build(Producer(records: records), memory, root, policy(capacity)).value
    assert memory.bytes == reference.bytes and built.counts.nodes == 747
    let found = lookupPaged(built, memory.input, default(StateKey), workLimits()).value
    assert found.verified.bytes == @[1'u8] and found.counts.nodes == 249
  var short = policy()
  short.proof.nodes = ElementLimit(248)
  assert validatePagedArtifact(Memory(bytes: reference.bytes).input, selected(reference, root),
      short).error == PagedStreamError.LimitExceeded
  var malformed = copyRecords(records)
  malformed[0].proof.nodes.add(default(EncodedStateNode))
  let invalid = pagedReference(default(StorageChainId), root, malformed)
  let refused = validatePagedArtifact(Memory(bytes: invalid.bytes).input, selected(invalid, root),
      policy())
  assert refused.error == PagedStreamError.InvalidFormat

proc growth() =
  ## Streamed sorted absence input scales past index-page boundaries under the same private work-space allowance.
  for size in [1, 64, 65, 1000]:
    var records = newSeq[LightStateProof](size)
    for index in 0..<size:
      var raw = default(array[31, byte])
      raw[0] = byte(index div 256)
      raw[1] = byte(index mod 256)
      records[index] = LightStateProof(key: StateKey(raw), proof: StateProof())
    let reference = pagedReference(default(StorageChainId), default(StateRoot), records)
    let memory = Memory(bytes: @[])
    let built = build(Producer(records: records), memory, default(StateRoot), policy()).value
    assert memory.bytes == reference.bytes and built.counts.proofs == uint64(3*size)
    for index in [0, size div 2, size-1]:
      let found = lookupPaged(built, memory.input, records[index].key, workLimits()).value
      assert found.verified.kind == StateLookupKind.Absent
proc cycle() =
  ## All source owners, callbacks, scratch, metadata and owned lookup temporaries retire before the next ARC sample.
  let records = emptyRecords()
  let memory = Memory(bytes: @[])
  let built = build(Producer(records: records), memory, default(StateRoot), policy()).value
  let checked = validatePagedArtifact(memory.input, built.manifest, policy()).value
  assert lookupPaged(checked, memory.input, key(0), workLimits()).value.verified.kind ==
      StateLookupKind.Absent
  assert lookupPaged(checked, memory.input, key(64), workLimits()).error ==
      PagedStreamError.UnknownKey
proc compaction() =
  ## Complete source bytes determine compaction; an independently valid same-root target knowledge change is refused.
  let original = Memory(bytes: @[])
  let artifact = build(Producer(records: emptyRecords()), original, default(StateRoot), policy()).value
  let target = initPagedHeader(default(StorageChainId), default(StateRoot), ManagedEpoch(2),
    LightDeltaSequence(0), artifact.header.geometry.entries, artifact.header.geometry.payloadBytes,
        policy().dataset).value
  let copied = Memory(bytes: @[])
  let complete = compactPagedArtifact(copied.output, original.input, artifact, target)
  assert complete.error == PagedStreamError.None
  var reference = pagedReference(default(StorageChainId), default(StateRoot), emptyRecords())
  reference.bytes.put(88, 2)
  reference.recommit()
  assert copied.bytes == reference.bytes
  assert complete.value.manifest.bytes == reference.manifest
  let mutated = Memory(bytes: @[], changeKnowledge: true)
  assert compactPagedArtifact(mutated.output, original.input, artifact, target).error ==
      PagedStreamError.ChangedInput
  let wrong = initPagedHeader(default(StorageChainId), default(StateRoot), ManagedEpoch(2),
    LightDeltaSequence(1), artifact.header.geometry.entries, artifact.header.geometry.payloadBytes,
        policy().dataset).value
  let untouched = Memory(bytes: @[])
  assert compactPagedArtifact(untouched.output, original.input, artifact, wrong).error ==
      PagedStreamError.ChangedInput
  assert untouched.writes == 0 and untouched.bytes.len == 0
  var limited = policy()
  limited.work.writeBytes = ByteLimit(0)
  let admitted = validatePagedArtifact(original.input, artifact.manifest, limited).value
  assert compactPagedArtifact(untouched.output, original.input, admitted, target).error ==
      PagedStreamError.LimitExceeded
  assert untouched.writes == 0
  original.bytes[4096] = 1
  assert compactPagedArtifact(untouched.output, original.input, artifact, target).error ==
      PagedStreamError.ChecksumMismatch

proc main() =
  ## Checked native execution covers algorithms/callback faults; native pin/publication and RSS qualification remain separate.
  let data = fixture()
  success(data)
  emptyAndReplay()
  strictCorruption(data)
  lookupCorruption(data)
  budgets(data)
  ioFaults(data)
  providerFaults(data)
  deepestProof()
  growth()
  compaction()
  let before = getOccupiedMem()
  for index in 0..<1000: cycle()
  recordArcRelease("storage_paged_stream", 1000, before, getOccupiedMem())
  echo "PASS paged streams: replay-bound construction, complete admission, authenticated bounded search and failure atomicity"
main()
