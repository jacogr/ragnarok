# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE129 inclusive ranges and authentic boundary paths, plus canonical hash-checked CE143 reads.

import std/[assertions, syncio]
import ../../support/[jamnp_topology_fixture, jamnp_read_exchange]
import ../../../src/jamnp-s/[read_stream, canonical_read]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, natural, composite]
import ../../../src/codec/state/[layout, trie, accounts, service_values]
import ../../../src/state/[store, snapshot_proof, trie_proof]
import ../../../src/crypto/primitives

proc key(id: byte): StateKey =
  ## Adjacent absent/present test keys expose inclusive range and sorted-contiguity rules.
  var raw = default(array[31, byte])
  raw[0] = id
  StateKey(raw)

proc source(extra: seq[StateEntry]): BlockSnapshotResult =
  ## Preserve full-map provenance while adding canonical service records to a structural fixture.
  let base = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)])
  assert base.error == GenesisError.None
  var entries: seq[StateEntry] = @[]
  for index in 0..<base.value.keyCount:
    let selected = base.value.keyAt(StateKeyIndex(index))
    let value = base.value.lookup(selected)
    assert value.error == StateStoreError.None
    entries.add(StateEntry(key: selected, value: value.value.bytes))
  for entry in extra: entries.add(entry)
  var wire = newSeq[byte](297)
  assert encodeOwnedHeader(base.value.header, wire).error == HeaderError.None
  result = captureBlockSnapshot(wire, entries, topologySettings())
  assert result.error == GenesisError.None

proc rangeRequest(hash: BlockHash, start, finish: StateKey, maximum: uint32): seq[byte] =
  ## Literal CE129 payload has two 31-byte inclusive keys and one E4 maximum, without a count.
  result = @[]
  for octet in array[32, byte](hash): result.add(octet)
  for octet in array[31, byte](start): result.add(octet)
  for octet in array[31, byte](finish): result.add(octet)
  for index in 0..<4: result.add(byte((maximum shr (8*index)) and 255))

proc request(kind: ReadKind, wire: seq[byte]): ReadRequest =
  ## Explicit successful admission precedes any request extraction.
  let decoded = decodeReadRequest(kind, wire)
  assert decoded.error == ReadError.None
  decoded.value

proc frames(wire: seq[byte], count: int): seq[seq[byte]] =
  ## Independently decode an exact bounded E4 message sequence, checking all suffixes.
  result = @[]
  var cursor = 0
  for message in 0..<count:
    assert wire.len-cursor >= 4
    var length = 0'u32
    for index in 0..<4: length = length or (uint32(wire[cursor+index]) shl (8*index))
    cursor += 4
    assert uint64(length) <= uint64(wire.len-cursor)
    var payload = newSeq[byte](int(length))
    for index in 0..<payload.len: payload[index] = wire[cursor+index]
    result.add(payload)
    cursor += payload.len
  assert cursor == wire.len, "no extra message/count/suffix is permitted"

proc checkRange(snapshot: BlockSnapshot, wire: seq[byte], expected: seq[StateEntry],
    start: StateKey) =
  ## Exact KVs and independently authenticated paths constrain node membership, uniqueness and order.
  let payloads = frames(wire, 2)
  var expectedPairs: seq[byte] = @[]
  for entry in expected:
    for octet in array[31, byte](entry.key): expectedPairs.add(octet)
    let length = encode(JamNatural(uint64(entry.value.len)))
    for index in 0..<length.len: expectedPairs.add(length.bytes[index])
    for octet in entry.value: expectedPairs.add(octet)
  assert payloads[1] == expectedPairs, "sorted contiguous inclusive KVs with canonical natural lengths"
  let boundary = payloads[0]
  assert boundary.len mod 64 == 0
  var nodes: seq[EncodedStateNode] = @[]
  for index in 0..<boundary.len div 64:
    var raw = default(array[64, byte])
    for offset in 0..<64: raw[offset] = boundary[index*64+offset]
    for prior in nodes: assert array[64, byte](prior) != raw, "boundary nodes must be unique"
    nodes.add(EncodedStateNode(raw))
  var queries = @[start]
  if expected.len > 0: queries.add(expected[^1].key)
  var covered = newSeq[bool](nodes.len)
  let limits = StateProofLimits(nodes: ElementLimit(256), valueBytes: ByteLimit(4*1024*1024))
  for query in queries:
    let proof = generateStateProof(snapshot.stateSnapshot, query, genesisStoreLimits().trie, limits)
    assert proof.error == StateProofError.None
    assert verifyStateProof(proof.value, snapshot.stateRoot, query, limits).error ==
        StateProofError.None
    var previous = -1
    for index in 0..<proof.value.len:
      let expectedNode = proof.value.nodeAt(index)
      assert expectedNode.error == StateProofError.None
      var position = -1
      for offset in 0..<nodes.len:
        if array[64, byte](nodes[offset]) == array[64, byte](expectedNode.value): position = offset
      assert position > previous, "every authenticated path node occurs with parents before children"
      covered[position] = true
      previous = position
  for present in covered: assert present, "no off-path nodes are permitted"

proc main() {.raises.} =
  ## Values straddle empty/small/natural-prefix boundaries; service lookup verifies full blob identity.
  let records = @[StateEntry(key: key(64), value: @[]), StateEntry(key: key(66), value: @[9'u8, 8]),
    StateEntry(key: key(68), value: newSeq[byte](129))]
  let blob = @[1'u8, 7, 9, 3]
  let hashed = blake2b256(blob)
  assert hashed.error == CryptoError.None
  let identity = array[32, byte](hashed.value)
  let account = serviceMetadataEntry(ServiceIndex(3), default(ServiceMetadata), ByteLimit(256))
  let preimage = servicePreimageEntry(ServiceIndex(3), ServicePreimageHash(identity), blob,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1024)))
  assert account.error == ServiceMetadataError.None and preimage.error == ServiceValueError.None
  var extra = records
  extra.add(account.value)
  extra.add(preimage.value)
  let captured = source(extra)
  let snapshot = captured.value
  let view = genesisView(captured)
  for start in [key(64), key(65)]:
    let payload = rangeRequest(snapshot.blockHash, start, key(68), 1048576)
    let reply = serveCanonicalRead(view, request(ReadKind.State, payload))
    assert reply.error == ReadError.None
    let expected = if array[31, byte](start)[0] == 64: records else: @[records[1], records[2]]
    checkRange(snapshot, reply.value.bytes, expected, start)
    exchangeRead(view, ReadKind.State, payload, reply.value.bytes, holdFin = true)
  let admittedState = request(ReadKind.State, rangeRequest(snapshot.blockHash, key(64), key(68), 1048576))
  assert captureReadReply(admittedState, @[0'u8, 0, 0, 0]).error == ReadError.InvalidRequest
  let admittedPreimage = request(ReadKind.Preimage, newSeq[byte](32))
  assert captureReadReply(admittedPreimage, newSeq[byte](8)).error == ReadError.InvalidRequest
  assert captureReadReply(admittedPreimage, @[255'u8, 255, 255, 255]).error ==
      ReadError.InvalidRequest
  assert decodeReadRequest(ReadKind.State, newSeq[byte](99)).error == ReadError.InvalidRequest
  let one = rangeRequest(snapshot.blockHash, key(64), key(68), 1)
  let single = serveCanonicalRead(view, request(ReadKind.State, one))
  assert single.error == ReadError.None and single.value.bytes.len > 1
  checkRange(snapshot, single.value.bytes, @[records[0]], key(64))
  exchangeRead(view, ReadKind.State, one, single.value.bytes)
  let boundedPayload = rangeRequest(snapshot.blockHash, key(64), key(68), 32842)
  let bounded = serveCanonicalRead(view, request(ReadKind.State, boundedPayload))
  assert bounded.error == ReadError.None and bounded.value.bytes.len <= 32842
  checkRange(snapshot, bounded.value.bytes, @[records[0], records[1]], key(64))
  let empty = rangeRequest(snapshot.blockHash, key(67), key(67), 1048576)
  let absent = serveCanonicalRead(view, request(ReadKind.State, empty))
  assert absent.error == ReadError.None
  checkRange(snapshot, absent.value.bytes, @[], key(67))
  exchangeRead(view, ReadKind.State, empty, absent.value.bytes)
  let reversed = rangeRequest(snapshot.blockHash, key(68), key(64), 1048576)
  assert serveCanonicalRead(view, request(ReadKind.State, reversed)).error ==
      ReadError.InvalidRequest
  exchangeRead(view, ReadKind.State, reversed, @[], refused = true)
  let insufficient = rangeRequest(snapshot.blockHash, key(67), key(67), 0)
  exchangeRead(view, ReadKind.State, insufficient, @[], refused = true)
  var hash: seq[byte] = @[]
  for octet in identity: hash.add(octet)
  let read = serveCanonicalRead(view, request(ReadKind.Preimage, hash))
  assert read.error == ReadError.None and frames(read.value.bytes, 1) == @[blob]
  exchangeRead(view, ReadKind.Preimage, hash, read.value.bytes, holdFin = true)
  let emptyHash = blake2b256(@[])
  assert emptyHash.error == CryptoError.None
  let emptyIdentity = array[32, byte](emptyHash.value)
  let emptyEntry = servicePreimageEntry(ServiceIndex(3), ServicePreimageHash(emptyIdentity), @[],
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1024)))
  assert emptyEntry.error == ServiceValueError.None
  let emptyView = genesisView(source(@[account.value, emptyEntry.value]))
  var emptyRequest: seq[byte] = @[]
  for octet in emptyIdentity: emptyRequest.add(octet)
  exchangeRead(emptyView, ReadKind.Preimage, emptyRequest, @[0'u8, 0, 0, 0])
  let wrong = servicePreimageEntry(ServiceIndex(3), ServicePreimageHash(identity), @[99'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1024)))
  assert wrong.error == ServiceValueError.None
  let inconsistent = genesisView(source(@[account.value, wrong.value]))
  assert serveCanonicalRead(inconsistent, request(ReadKind.Preimage, hash)).error ==
      ReadError.Unavailable
  exchangeRead(inconsistent, ReadKind.Preimage, hash, @[], refused = true)
  exchangeRead(view, ReadKind.Preimage, newSeq[byte](32), @[], refused = true)
  exchangeRead(view, ReadKind.State, newSeq[byte](97), @[], refused = true)
  let uninitializedView = default(ChainView)
  let uninitializedRequest = default(ReadRequest)
  assert serveCanonicalRead(uninitializedView, uninitializedRequest).error ==
      ReadError.InvalidRequest
  echo "jamnp canonical read: state boundaries and canonical preimages passed"
try:
  main()
except:
  quit 2 # Fixture/native setup exceptions cannot satisfy a protocol transcript.
