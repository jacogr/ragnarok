# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete fixtures are prepared outside pressure; fresh bounded writers/readers retain no resident graph or index.
import std/[algorithm, assertions, cmdline, syncio]
import ../support/[storage_io, storage_allocations, full_paged_reference]
import ../../src/storage/full/paged/[codec as full_paged_codec, stream as full_paged_stream,
    build as full_paged_build, store as full_paged_store]
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/node/records as node_records
import ../../src/storage/paged/[codec as paged_codec, io as paged_io]
import ../../src/storage/managed/manifest as managed_manifest
import ../../src/storage/node/repository as node_repository
import ../../src/storage/database_identity
import ../../src/storage/file/errors as file_errors
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
const ValueBytes = 1048576 ## Identical per-value policy for shallow small/large and maximum-depth cases.
proc descriptors(): cint {.importc: "ragnarok_paged_descriptors",
    header: "storage_paged_resources.h".}
  ## Reuse SDK descriptor observations; the observation directory handle is excluded.
proc usage(selector: cint): clonglong {.importc: "ragnarok_paged_usage",
    header: "storage_paged_resources.h".}
  ## Native process peak RSS/faults use actual platform units, including runtime/provider/translator allocations.
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset counters without provider failure injection or changing hash semantics.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## The finite case plan stays below the observer's signed counter ceiling.
func valueSize(count: int): int =
  ## A cardinality panel complements long-value pressure while inheriting the identical1MiB per-value policy.
  if count == 2048: 36864 else: ValueBytes
func key(ordinal: uint64, count: int): StateKey =
  ## Two-entry fixtures split at bit247; other fixtures spread complete keys over a bounded integer prefix.
  var raw = default(array[31, byte])
  if count == 2:
    raw[30] = byte(ordinal) # The deep fixture has exactly248 branches and two leaves.
  else:
    for index in 0..<8: raw[index] = byte((ordinal shr ((7-index)*8)) and 255) # MSB key order.
  StateKey(raw)
func limits(cache: int): FullPagedStreamLimits =
  ## Dataset scaling never changes per-value, history, workspace, scratch or finite work policy.
  let calls = ElementLimit(1000000000)
  let bytes = ByteLimit(1000000000000'u64)
  FullPagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(16384), bytes: ByteLimit(
      200000000)),
    trie: StateTrieLimits(items: ElementLimit(4096), nodes: TrieNodeLimit(16384),
      perValue: ByteLimit(ValueBytes), totalValueBytes: ByteLimit(134217728)),
    roots: ElementLimit(1), cachePages: ElementLimit(uint64(cache)), workingBytes: ByteLimit(
        16777216),
    scratchBytes: ByteLimit(32768), work: FullPagedWorkLimits(ioCalls: calls, hashes: calls,
      visits: calls, readBytes: bytes, writeBytes: bytes))
func config(root: StateRoot, cache: int): FullPagedNativeConfig =
  ## Measured construction uses a bounded source-file callback and never retains the fixture's complete map.
  FullPagedNativeConfig(root: root, limits: limits(cache),
    construction: FullPagedConstructionLimits(producerCalls: ElementLimit(10000),
      ioCalls: ElementLimit(1000000000), hashes: ElementLimit(1000000000),
      readBytes: ByteLimit(1000000000000'u64), writeBytes: ByteLimit(1000000000000'u64)))
func rootHex(root: StateRoot): string =
  ## Cross-process identity uses exactly64 lowercase hex digits, independent of selected disk metadata.
  const digits = "0123456789abcdef"
  result = ""
  for octet in array[32, byte](root):
    result.add(digits[int(octet shr 4)]) # High nibble precedes low nibble.
    result.add(digits[int(octet and 15)])
proc number(text: string, maximum: uint64): uint64 =
  ## Finite trusted case arguments still prove every decimal multiply/add before narrowing or allocation.
  result = 0
  assert text.len > 0 and text.len <= 10
  for character in text:
    assert character in {'0'..'9'} # No signs, whitespace or alternate numeric representation.
    let digit = uint64(ord(character)-ord('0'))
    assert digit <= maximum and result <= (maximum-digit) div 10
    result = result*10+digit
proc parseRoot(text: string): StateRoot =
  ## Expected full-map root arrives independently from the outside-pressure complete-map fixture producer.
  assert text.len == 64
  const digits = "0123456789abcdef"
  var raw = default(array[32, byte])
  for index in 0..<32:
    var a, b = -1
    for nibble in 0..<16:
      if text[index*2] == digits[nibble]: a = nibble # Canonical lowercase only.
      if text[index*2+1] == digits[nibble]: b = nibble
    assert a >= 0 and b >= 0
    raw[index] = byte(a*16+b)
  StateRoot(raw)
proc prepareFixture(path: string, count: int) {.raises.} =
  ## Resident map/export/reference tree intentionally run in a separate unconstrained process, never in measured storage execs.
  var entries = newSeq[StateEntry](count)
  for ordinal in 0..<count:
    var value: seq[byte] = @[]
    if ordinal != count-1:
      value = newSeq[byte](valueSize(count)) # Retain one independently tested present-empty final leaf.
      for index in 0..<value.len: value[index] = byte((index+ordinal) mod 251)
    entries[ordinal] = StateEntry(key: key(uint64(ordinal), count), value: value)
  let policy = limits(0)
  let independent = stateTrieRoot(entries, policy.trie)
  assert independent.error == StateTrieError.None
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: policy.trie)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](independent.value.root)
  let exported = trie.exportFullTrie(TrieExportLimits(records: TrieNodeLimit(16384),
    valueBytes: policy.trie.totalValueBytes)).value
  var records = exported.records
  records.sort(proc(a, b: TrieRecord): int = compareFullHash(array[32, byte](a.digest), array[32,
      byte](b.digest)))
  if count == 2: assert records.len == 250 # Full depth248 is measured rather than merely logically budgeted.
  var payload = 0'u64
  for record in records:
    payload += uint64(encodeFullPagedRecord(record, policy.trie.perValue).value.len) # Finite16384-record fixture.
  let root = independent.value.root
  let claim = FullPagedRoot(root: root, entries: uint64(count), nodes: uint64(records.len),
    valueBytes: uint64(count-1)*uint64(valueSize(count)))
  let header = initFullPagedHeader(default(StorageChainId), root, ManagedEpoch(1),
      RepositoryGeneration(0),
    uint64(records.len), payload, [claim], policy.dataset).value
  var bytes: seq[byte] = @[]
  bytes.append(header.bytes)
  var offset = 0'u64
  for record in records:
    let size = uint64(encodeFullPagedRecord(record, policy.trie.perValue).value.len)
    bytes.append(initFullPagedRow(header.geometry, record.digest, offset, size).value.bytes)
    offset += size
  while uint64(bytes.len) < uint64(header.geometry.payloadOffset): bytes.add(0) # Canonical index padding.
  for record in records: bytes.append(encodeFullPagedRecord(record,
      policy.trie.perValue).value) # Complete independent body.
  while uint64(bytes.len) < uint64(header.geometry.treeOffset): bytes.add(0) # Canonical payload padding.
  let pageRoot = tree(bytes, int(header.geometry.dataPages), 0, int(header.geometry.treeLeaves))
  assert uint64(bytes.len) == header.geometry.byteLength
  let manifest = encodeFullPagedManifest(header, FullPagedDigest(pageRoot)).value.bytes.value
  writeFile(path, bytes)
  writeFile(path & ".current", manifest)
  echo count, "\t", rootHex(root), "\t", records.len, "\t", payload, "\t",
      header.geometry.dataPages,
    "\t", header.geometry.byteLength
proc producer(file: File, header: FullPagedHeader, perValue: ByteLimit): FullPagedProducer =
  ## Synchronous callback reads only one fixed descriptor and one bounded canonical record from an immutable source file.
  proc next(pass: int, ordinal: uint64, output: var TrieRecord): FullPagedProducerStep {.closure.} =
    ## Complete pass replay/fingerprint and graph admission stay in the production constructor.
    if ordinal >= header.geometry.entries: return FullPagedProducerStep.End
    var row = default(array[PagedDescriptorBytes, byte])
    try:
      setFilePos(file, int64(4096+ordinal*uint64(PagedDescriptorBytes))) # Independent fixed-width index.
      if readBuffer(file, addr row[0], row.len) != row.len: return FullPagedProducerStep.Failed
      let decoded = decodeFullPagedRow(row, header.geometry)
      if decoded.error != FullPagedError.None: return FullPagedProducerStep.Failed
      let descriptor = decoded.value
      if descriptor.byteLength > uint64(ValueBytes+97): return FullPagedProducerStep.Failed
      var raw = newSeq[byte](int(descriptor.byteLength))
      assert raw.len >= 72
      setFilePos(file, int64(uint64(header.geometry.payloadOffset)+descriptor.offset))
      if readBuffer(file, addr raw[0], raw.len) != raw.len: return FullPagedProducerStep.Failed
      let record = decodeFullPagedRecord(raw, descriptor.digest, perValue)
      if record.error != FullPagedError.None: return FullPagedProducerStep.Failed
      output = record.value
      FullPagedProducerStep.Item
    except:
      return FullPagedProducerStep.Failed # Source seek/IO uncertainty is never a successful producer end.
  next
type StreamCheck = ref object ## Private bounded callback state retains no value bytes, physical records or native owner.
  next: int
proc entryVisitor(owner: StreamCheck, count: int): FullPagedEntryVisitor =
  ## Verify every complete-root key/value in sorted order without materializing any map inside pressure.
  proc visit(ordinal: uint64, selected: StateKey, value: openArray[byte]): bool {.closure.} =
    ## Only a fully processed value advances the witness; borrowed bytes never outlive this synchronous callback.
    assert ordinal == uint64(owner.next) and owner.next < count
    assert array[31, byte](selected) == array[31, byte](key(ordinal, count))
    let expected = if owner.next == count-1: 0 else: valueSize(count)
    assert value.len == expected
    for index in 0..<value.len: assert value[index] == byte((index+owner.next) mod 251) # Every selected map byte.
    inc owner.next
    true
  visit
proc run(mode, path, source: string, count, cache: int, root: StateRoot, records, payload: uint64) =
  ## One fresh native exec measures authoring or strict admission; all source/target descriptors and heap retire before receipt formatting.
  let policy = config(root, cache)
  let claim = FullPagedRoot(root: root, entries: uint64(count), nodes: records,
    valueBytes: uint64(count-1)*uint64(valueSize(count)))
  let header = initFullPagedHeader(default(StorageChainId), root, ManagedEpoch(1),
      RepositoryGeneration(0),
    records, payload, [claim], policy.limits.dataset).value
  let baseline = occupiedStorageBytes()
  let handles = descriptors()
  var opened = baseline
  var openHandles = handles
  var queries = 0
  var streamedEntries = 0
  resetIo()
  resetHash(0)
  block:
    if mode == "prepare":
      # Source FILE and producer are scoped inside the measured exec; fixture preparation is never repeated here.
      var input: File
      assert open(input, source, fmRead)
      defer: close(input) # No callback escapes the synchronous constructor or this source lifetime.
      var writer = default(FullPagedWriter)
      defer:
        if writer.opened: discard writer.close # Failed tests still explicitly retire native storage owners.
      assert initializeFullPagedWriter(writer, path, policy, [claim], producer(input, header,
        policy.limits.trie.perValue), records, payload).error == FullPagedNativeError.None
      assert writer.selected.value.byteLength == header.geometry.byteLength
      opened = occupiedStorageBytes()
      openHandles = descriptors()
      assert writer.close == FileError.None
    else:
      # Strict reader performs complete graph admission before any populated spread, empty or absent query.
      var reader = default(FullPagedReader)
      defer:
        if reader.opened: discard reader.close # No reader pin survives success or an assertion failure.
      assert openFullPagedReader(reader, path, policy).error == FullPagedNativeError.None
      assert reader.selected.value.byteLength == header.geometry.byteLength
      opened = occupiedStorageBytes()
      openHandles = descriptors()
      for iteration in 0..<16:
        let ordinal = (iteration*17) mod (count-1)
        let found = reader.lookup(root, key(uint64(ordinal), count))
        assert found.error == FullPagedNativeError.None and found.value.present
        let value = found.value.bytes
        assert value.len == valueSize(count)
        for index in 0..<value.len: assert value[index] == byte((index+ordinal) mod 251) # Every returned byte.
        inc queries
      let empty = reader.lookup(root, key(uint64(count-1), count))
      assert empty.error == FullPagedNativeError.None and empty.value.present and
          empty.value.bytes.len == 0
      assert not reader.lookup(root, key(uint64(count+128), count)).value.present
      var unknown = default(array[32, byte])
      unknown[0] = 255
      let missingRoot = reader.lookup(StateRoot(unknown), key(0, count))
      assert missingRoot.error == FullPagedNativeError.GraphFailure
      assert missingRoot.graphError == FullPagedStreamError.UnknownRoot
      queries += 3
      let streamed = StreamCheck()
      let complete = reader.visitEntries(root, entryVisitor(streamed, count))
      assert complete.error == FullPagedNativeError.None and complete.value.visits == records
      assert streamed.next == count
      streamedEntries = streamed.next
      assert reader.close == FileError.None
  let released = occupiedStorageBytes()
  let finalHandles = descriptors()
  assert opened >= baseline and opened-baseline < 65536 and released == baseline
  assert openHandles > handles and finalHandles == handles
  let rss = usage(0)
  let minor = usage(1)
  let major = usage(2)
  assert rss > 0 and minor >= 0 and major >= 0
  echo mode, "\t", count, "\t", cache, "\t", rootHex(root), "\t", header.geometry.byteLength,
    "\t", header.geometry.dataPages, "\t", baseline, "\t", opened, "\t", released,
    "\t", handles, "\t", openHandles, "\t", finalHandles, "\t", ioCalls(readIo), "\t", ioCalls(
        writeIo),
    "\t", hashCalls(), "\t", queries, "\t", rss, "\t", minor, "\t", major, "\t", streamedEntries
proc main() {.raises.} =
  ## Finite shallow/deep cases prove all argument conversions and derived extents before native IO.
  assert paramCount() in [4, 8]
  if paramCount() == 4:
    assert paramStr(1) == "fixture" and paramStr(3) in ["2", "8", "72", "2048"] and paramStr(4) == "0"
    prepareFixture(paramStr(2), int(number(paramStr(3), 2048)))
  else:
    assert paramStr(1) in ["prepare", "open"] and paramStr(4) in ["2", "8", "72", "2048"]
    assert paramStr(5) in ["0", "1"]
    run(paramStr(1), paramStr(2), paramStr(3), int(number(paramStr(4), 2048)),
      int(number(paramStr(5), 1)), parseRoot(paramStr(6)), number(paramStr(7), 16384),
      number(paramStr(8), 200000000))
try:
  main()
except:
  quit(2) # A fixture IO failure cannot become a valid native resource receipt.
