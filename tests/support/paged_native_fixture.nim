# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent root-bound native paged fixtures and synchronous replayable test producers.
import std/assertions
import ../../src/storage/[paged_store, paged_codec, paged_stream, light_state_cache, state_proof, full_state_trie]
import ../../src/codec/[bounded, state_layout, state_trie]
type PagedNativeFixture* = object ## Independent complete-map roots constrain two different same-shape paged knowledge stores.
  config*: PagedNativeConfig
  records*: seq[LightStateProof]
  payload*: uint64
func pagedKey*(first: byte): StateKey =
  ## Canonical test identities differ at the highest serialized octet.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
func pagedPolicy*(): PagedStreamLimits =
  ## Finite dataset, per-proof, scratch/cache and per-stream-phase work ceilings remain independent.
  let elements = ElementLimit(1000000)
  let bytes = ByteLimit(100000000)
  PagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(10000), bytes: bytes),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(10000)),
    workingBytes: ByteLimit(100000), cachePages: ElementLimit(1),
    work: PagedWorkLimits(ioCalls: elements, producerCalls: elements, pageHashes: elements,
      proofs: elements, nodes: elements, readBytes: bytes, writeBytes: bytes, valueBytes: bytes))
proc nativeFixture*(value: byte): PagedNativeFixture =
  ## The independent complete-map root calculator anchors trie-generated query evidence.
  var raw = newSeq[byte](33)
  raw[0] = value
  let entries = @[StateEntry(key: pagedKey(0), value: raw), StateEntry(key: pagedKey(128), value: @[])]
  let limits = StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(10000),
    totalValueBytes: ByteLimit(20000), nodes: TrieNodeLimit(1000))
  let root = stateTrieRoot(entries, limits).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  result = PagedNativeFixture(config: PagedNativeConfig(root: root, limits: pagedPolicy()),
      records: @[])
  for first in [0'u8, 128, 255]:
    let proof = trie.prove(pagedKey(first), pagedPolicy().proof).value
    result.payload += 41+uint64(proof.nodes.len)*64+uint64(proof.value.len)
    result.records.add(LightStateProof(key: pagedKey(first), proof: proof))
proc nativeProducer*(records: seq[LightStateProof]): PagedProducer =
  ## Only test fixtures retain a batch; production consumes one stable record at each requested ordinal.
  proc next(pass: int, ordinal: uint64, output: var LightStateProof): PagedProducerStep {.closure.} =
    if ordinal >= uint64(records.len): return PagedProducerStep.End
    output = records[int(ordinal)]
    PagedProducerStep.Item
  next
