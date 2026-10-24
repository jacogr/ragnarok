# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Constant-size proof templates generate populated paged datasets; fresh consumers measure strict admission and spread reads.
import std/[assertions, cmdline, syncio]
import ../support/[storage_io, storage_allocations]
import ../../src/storage/[paged_store, paged_io, paged_stream, paged_codec, state_proof,
  light_state_cache, full_state_trie, light_delta, file_errors, managed_manifest]
import ../../src/codec/[bounded, state_layout, state_trie]
type Fixture = object ## Only three bounded proofs and one cross-page value survive independent complete-map construction.
  config: PagedNativeConfig
  first, absent, last: LightStateProof
proc descriptors(): cint {.importc: "ragnarok_paged_descriptors",
    header: "storage_paged_resources.h".}
  ## SDK-owned descriptor enumeration excludes its own observation handle and refuses unsupported scans.
proc usage(selector: cint): clonglong {.importc: "ragnarok_paged_usage",
    header: "storage_paged_resources.h".}
  ## Actual SDK getrusage samples include native runtime/provider/translator resources after storage work, before final receipt formatting.
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Count maintained cryptography without fault injection or altered proof semantics.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## The bounded source-owned dataset plan stays below the observer's signed counter ceiling.
func key(ordinal: uint64): StateKey =
  ## Fixed big-endian prefixes preserve numeric sorting and stay strictly below the all-ones final key.
  var raw = default(array[31, byte])
  for index in 0..<8: raw[index] = byte((ordinal shr ((7-index)*8)) and 255)
  StateKey(raw)
func lastKey(): StateKey =
  ## This retained present-empty leaf is independent of dataset cardinality.
  var raw = default(array[31, byte])
  for index in 0..<raw.len: raw[index] = 255
  StateKey(raw)
func limits(cache: int): PagedStreamLimits =
  ## All runs inherit identical finite bounds except the explicit zero/one page treatment.
  let calls = ElementLimit(1000000000)
  let bytes = ByteLimit(1000000000000'u64)
  PagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(1000000), bytes: ByteLimit(
      1000000000)),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(8192)),
    workingBytes: ByteLimit(65536), cachePages: ElementLimit(uint64(cache)),
    work: PagedWorkLimits(ioCalls: calls, producerCalls: calls, pageHashes: calls, proofs: calls,
      nodes: calls, readBytes: bytes, writeBytes: bytes, valueBytes: bytes))
proc fixture(cache: int): Fixture =
  ## An independent complete two-entry map anchors nonempty-root proofs, with no count-sized resident input.
  var value = newSeq[byte](4097)
  for index in 0..<value.len: value[index] = byte(index mod 251)
  let entries = @[StateEntry(key: key(0), value: value), StateEntry(key: lastKey(), value: @[])]
  let policy = StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(8192),
    totalValueBytes: ByteLimit(8192), nodes: TrieNodeLimit(1000))
  let root = stateTrieRoot(entries, policy).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: policy)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  result = default(Fixture)
  result.config = PagedNativeConfig(root: root, limits: limits(cache))
  result.first = LightStateProof(key: key(0), proof: trie.prove(key(0),
      result.config.limits.proof).value)
  result.absent = LightStateProof(key: key(1), proof: trie.prove(key(1),
      result.config.limits.proof).value)
  result.last = LightStateProof(key: lastKey(), proof: trie.prove(lastKey(),
      result.config.limits.proof).value)
  assert result.first.proof.nodes.len == 2 and result.absent.proof.nodes.len == 2 and
    result.last.proof.nodes.len == 2
proc producer(source: Fixture, count: uint64): PagedProducer =
  ## The borrowed synchronous stream reuses three constant templates and retains no record batch or whole index.
  proc next(pass: int, ordinal: uint64, output: var LightStateProof): PagedProducerStep {.closure.} =
    if ordinal >= count: return PagedProducerStep.End
    if ordinal == 0: output = source.first
    elif ordinal == count-1: output = source.last
    else:
      # Any nonzero prefix below the all-ones leaf has the same independently complete absence path.
      output = source.absent
      output.key = key(ordinal)
    PagedProducerStep.Item
  next
proc rootHex(root: StateRoot): string =
  ## Emit independently recomputed root identity for cross-process attribution, never inferred from disk metadata.
  const digits = "0123456789abcdef"
  result = ""
  for value in array[32, byte](root):
    result.add(digits[int(value shr 4)])
    result.add(digits[int(value and 15)])
proc run(mode, path: string, count: uint64, cache: int) =
  ## Each executable invocation owns a single preparation or fresh admission; all resources retire before final samples.
  let source = fixture(cache)
  let payload = count*169+4097
  let shape = pagedGeometry(count, payload, source.config.limits.dataset).value
  let baseline = occupiedStorageBytes()
  let handles = descriptors()
  assert handles >= 3
  var opened = baseline
  var openHandles = handles
  var checked = 0
  resetIo()
  resetHash(0)
  block:
    if mode == "prepare":
      # The writer is also measured under any enclosing no-swap limit and closes before a separate consumer starts.
      var writer = default(PagedWriter)
      defer:
        if writer.opened: discard writer.close
      assert initializePagedWriter(writer, path, source.config, producer(source, count), count,
        payload).error == PagedNativeError.None
      assert writer.selected.value.epoch == ManagedEpoch(1)
      opened = occupiedStorageBytes()
      openHandles = descriptors()
      assert writer.close == FileError.None
    else:
      # Full strict admission authenticates the populated selected artifact before any spread/cyclic query succeeds.
      var reader = default(PagedReader)
      defer:
        if reader.opened: discard reader.close
      assert openPagedReader(reader, path, source.config).error == PagedNativeError.None
      assert reader.selected.value.epoch == ManagedEpoch(1)
      assert reader.selected.value.sequence == LightDeltaSequence(0)
      opened = occupiedStorageBytes()
      openHandles = descriptors()
      for cycle in 0..<4:
        for step in 0..<257:
          # A deterministic coprime stride spreads across index and payload pages; cycles repeat the same requests.
          let ordinal = (uint64(step)*104729) mod (count-1)
          let query = reader.lookup(key(ordinal), source.config.limits.work)
          assert query.error == PagedNativeError.None
          if ordinal == 0:
            assert query.value.kind == StateLookupKind.Present and query.value.bytes.len == 4097
            for index, value in query.value.bytes: assert value == byte(index mod 251)
          else:
            assert query.value.kind == StateLookupKind.Absent
          checked += 1
      assert reader.lookup(lastKey(), source.config.limits.work).value.kind ==
          StateLookupKind.Present
      assert reader.lookup(lastKey(), source.config.limits.work).value.bytes.len == 0
      assert reader.lookup(key(count+128), source.config.limits.work).error ==
          PagedNativeError.UnknownKey
      assert reader.close == FileError.None
  let released = occupiedStorageBytes()
  let finalHandles = descriptors()
  assert opened >= baseline and opened-baseline < 65536 and released == baseline
  assert openHandles > handles and finalHandles == handles
  let hashes = hashCalls()
  assert hashes > 0
  let rss = usage(0)
  let minor = usage(1)
  let major = usage(2)
  assert rss > 0 and minor >= 0 and major >= 0
  echo mode, "\t", count, "\t", cache, "\t", rootHex(source.config.root), "\t", shape.byteLength,
    "\t", shape.dataPages, "\t", baseline, "\t", opened, "\t", released, "\t", handles,
    "\t", openHandles, "\t", finalHandles, "\t", ioCalls(readIo), "\t", ioCalls(writeIo),
    "\t", hashes, "\t", checked, "\t", rss, "\t", minor, "\t", major
proc main() =
  ## A deliberately finite case plan bounds arithmetic, workload and all observer counters before native IO.
  assert paramCount() == 4 and paramStr(1) in ["prepare", "open"]
  assert paramStr(3) in ["16384", "327680"] and paramStr(4) in ["0", "1"]
  let count = if paramStr(3) == "16384": 16384'u64 else: 327680'u64
  let cache = if paramStr(4) == "0": 0 else: 1
  run(paramStr(1), paramStr(2), count, cache)
main()
