# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked response strength is explicit: trusted-root contiguous state, full content hashes and query-bound structural blocks.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[read_stream, read_validation, canonical_read]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, assurances, tickets, composite, block_codec]
import ../../../src/codec/state/[layout, trie]
import ../../../src/state/range_proof
import ../../../src/crypto/primitives
import ../../support/jamnp_topology_fixture
proc frame(body: openArray[byte]): seq[byte] =
  ## Independently supplied E4 framing is exact and has no element-count prefix.
  result = @[]
  for index in 0..<4: result.add(byte((uint32(body.len) shr (8*index)) and 255))
  for octet in body: result.add(octet)
proc limits(): ReadVerificationLimits =
  ## Trusted local ceilings do not turn decoded blocks into execution/adoption certificates.
  let maximum = ByteLimit(8388608)
  ReadVerificationLimits(wireBytes: maximum, blocks: ElementLimit(64), map: genesisStoreLimits().trie,
    frame: FrameConfig(cores: CoreCount(4), validators: ValidatorCount(12), epochSlots: EpochSlots(12),
      ticketLimit: TicketLimit(16), maxBytes: maximum,
      preimages: PreimageLimits(items: ElementLimit(8), perBlob: maximum, totalBlobBytes: maximum)))
proc snapshot(slot: uint32, parent = unavailableGenesis()): BlockSnapshotResult =
  ## Structural fixtures bind exact headers/body bytes and explicit parents without claiming valid execution or signatures.
  let captured = topologyCaptured([topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)],
    atSlot = slot, parent = parent)
  assert captured.error == GenesisError.None
  var body = newSeq[byte](304)
  assert encodeOwnedHeader(captured.value.header, body.toOpenArray(0, 296)).error ==
      HeaderError.None
  for index in 297..<304: body[index] = 0 # Seven canonical empty extrinsic counts.
  let complete = captured.value.withBlockBody(body)
  assert complete.error == GenesisError.None
  complete
proc body(saved: BlockSnapshotResult): seq[byte] =
  ## Independently encode the known structural fixture rather than reading the verifier's output.
  result = newSeq[byte](304)
  assert encodeOwnedHeader(saved.value.header, result.toOpenArray(0, 296)).error == HeaderError.None
  for index in 297..<304: result[index] = 0
proc blocks(anchor: BlockHash, direction: byte, maximum: uint32): ReadRequest =
  ## Literal fixed request identity/direction/u32 is independent of response validation.
  var payload: seq[byte] = @[]
  for octet in array[32, byte](anchor): payload.add(octet)
  payload.add(direction)
  for index in 0..<4: payload.add(byte((maximum shr (8*index)) and 255))
  decodeReadRequest(ReadKind.Blocks, payload).value
proc state(anchor: BlockHash, start, finish: StateKey, maximum = high(uint32)): ReadRequest =
  ## State bounds are inclusive31-byte serialized identities; no posterior root is supplied on the wire.
  var payload: seq[byte] = @[]
  for octet in array[32, byte](anchor): payload.add(octet)
  for octet in array[31, byte](start): payload.add(octet)
  for octet in array[31, byte](finish): payload.add(octet)
  for index in 0..<4: payload.add(byte((maximum shr (8*index)) and 255))
  decodeReadRequest(ReadKind.State, payload).value
proc main() =
  ## An invalid later component never exposes an earlier checked block/page prefix.
  let parent = snapshot(7)
  let child = snapshot(8, parent)
  let grandchild = snapshot(9, child)
  let source = captureReadSource(parent)
  assert source.error == ReadVerificationError.None and source.value.valid
  assert captureReadSource(unavailableGenesis()).error == ReadVerificationError.NoSource
  let policy = limits()
  let noSource = default(ReadSource)
  assert verifyReadReply(default(ReadRequest), [], noSource, policy).error ==
      ReadVerificationError.InvalidRequest
  let blob = @[1'u8, 2, 3, 4]
  let digest = blake2b256(blob).value
  var query: seq[byte] = @[]
  for octet in array[32, byte](digest): query.add(octet)
  let preimage = decodeReadRequest(ReadKind.Preimage, query).value
  let checked = verifyReadReply(preimage, frame(blob), noSource, policy)
  assert checked.error == ReadVerificationError.None and checked.value.valid
  assert checked.value.kind == ReadKind.Preimage and checked.value.preimageBytes == blob
  var extracted = checked.value.preimageBytes
  extracted[0] = 99
  assert checked.value.preimageBytes == blob
  assert verifyReadReply(preimage, frame(@[1'u8, 2, 3]), noSource, policy).error ==
      ReadVerificationError.HashMismatch
  query = @[]
  for octet in array[32, byte](blake2b256([]).value): query.add(octet)
  let emptyBlob = decodeReadRequest(ReadKind.Preimage, query).value
  assert verifyReadReply(emptyBlob, @[0'u8, 0, 0, 0], noSource, policy).value.preimageBytes.len == 0
  assert verifyReadReply(preimage, @[5'u8, 0, 0, 0], noSource, policy).error ==
      ReadVerificationError.InvalidFormat
  var descending = body(child)
  for octet in body(parent): descending.add(octet)
  let down = blocks(child.value.blockHash, 1, 2)
  let bound = verifyReadReply(down, frame(descending), source.value, policy)
  assert bound.error == ReadVerificationError.None and bound.value.blockCount == 2
  assert array[32, byte](bound.value.hashAt(0)) == array[32, byte](child.value.blockHash)
  assert array[32, byte](bound.value.hashAt(1)) == array[32, byte](parent.value.blockHash)
  assert bound.value.blockAt(0).blockInfo.error == FrameError.None
  let tooMany = blocks(child.value.blockHash, 1, 1)
  assert verifyReadReply(tooMany, frame(descending), source.value, policy).error ==
      ReadVerificationError.InvalidSequence
  assert verifyReadReply(blocks(parent.value.blockHash, 1, 2), frame(descending), source.value,
      policy).error == ReadVerificationError.HashMismatch
  assert verifyReadReply(blocks(parent.value.blockHash, 2, 2), frame(descending), source.value,
      policy).error == ReadVerificationError.InvalidRequest
  var ascending = body(child)
  for octet in body(grandchild): ascending.add(octet)
  let up = blocks(parent.value.blockHash, 0, 2)
  assert verifyReadReply(up, frame(ascending), source.value, policy).value.blockCount == 2
  var repeated = body(child)
  for octet in body(child): repeated.add(octet)
  assert verifyReadReply(up, frame(repeated), source.value, policy).error ==
      ReadVerificationError.InvalidSequence
  var short = body(child)
  let parentWire = body(parent)
  for index in 0..<100: short.add(parentWire[index])
  let truncated = verifyReadReply(down, frame(short), source.value, policy)
  assert truncated.error == ReadVerificationError.BlockFailure
  assert truncated.blockFailure.error != FrameError.None
  assert verifyReadReply(blocks(parent.value.blockHash, 1, 1), frame([]), source.value,
      policy).error == ReadVerificationError.InvalidSequence
  assert verifyReadReply(blocks(parent.value.blockHash, 1, 0), frame([]), source.value,
      policy).value.blockCount == 0
  var constrained = policy
  constrained.blocks = ElementLimit(1)
  assert verifyReadReply(down, frame(descending), source.value, constrained).error ==
      ReadVerificationError.LimitExceeded
  var upper = default(array[31, byte])
  for index in 0..<31: upper[index] = 255
  let pageRequest = state(parent.value.blockHash, default(StateKey), StateKey(upper))
  let view = genesisView(parent)
  let wire = serveCanonicalRead(view, pageRequest)
  assert wire.error == ReadError.None
  let page = verifyReadReply(pageRequest, wire.value.bytes, source.value, policy)
  assert page.error == ReadVerificationError.None and page.value.statePage.complete
  assert page.value.statePage.len == parent.value.keyCount
  assert array[32, byte](page.value.statePage.root) == array[32, byte](parent.value.stateRoot)
  let other = captureReadSource(child).value
  assert verifyReadReply(pageRequest, wire.value.bytes, other, policy).error ==
      ReadVerificationError.IdentityMismatch
  let small = state(parent.value.blockHash, default(StateKey), StateKey(upper), 1)
  assert verifyReadReply(small, wire.value.bytes, source.value, policy).error ==
      ReadVerificationError.LimitExceeded
  let last = parent.value.keyAt(StateKeyIndex(parent.value.keyCount-1))
  let oneRequest = state(parent.value.blockHash, last, last, 0)
  let oneWire = serveCanonicalRead(view, oneRequest)
  assert oneWire.error == ReadError.None
  let one = verifyReadReply(oneRequest, oneWire.value.bytes, source.value, policy)
  assert one.error == ReadVerificationError.None and one.value.statePage.len == 1
  var malformed = frame(newSeq[byte](63))
  for octet in frame([]): malformed.add(octet)
  assert verifyReadReply(pageRequest, malformed, source.value, policy).error ==
      ReadVerificationError.InvalidFormat
  var huge = newSeq[byte](31)
  huge.add(255)
  for index in 0..<8: huge.add(255)
  var hugeWire = frame([])
  for octet in frame(huge): hugeWire.add(octet)
  assert verifyReadReply(pageRequest, hugeWire, source.value, policy).error ==
      ReadVerificationError.InvalidFormat
  echo "jamnp read validation: trusted state, full preimage hashes and block query binding passed"
main()
