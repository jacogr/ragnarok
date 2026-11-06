# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal raw TLS responses test exact outbound framing; bytes remain explicitly untrusted, not proof/adoption authority.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[read_stream, read_client]
import ../../../src/quic/transport
import ../../../src/codec/bounded
import ../../support/jamnp_read_client_exchange
proc main() {.raises.} =
  ## Default/invalid requests grant no stream; malformed/truncated responses grant no completed owner.
  var route = default(ReadClientRoute)
  assert route.configure(default(ReadRequest)) == ReadError.InvalidRequest
  assert route.take().error == ReadError.Unavailable
  assert decodeReadRequest(ReadKind.Guarantee, []).error == ReadError.InvalidRequest
  let guarantee = @[1'u8, 2, 3]
  exchangeClient(ReadKind.Guarantee, guarantee, @[], holdFin = true, maximum = ByteLimit(0), budget = 0)
  exchangeClient(ReadKind.Guarantee, guarantee, @[0'u8], maximum = ByteLimit(0),
      failure = ReadError.InvalidRequest)
  assert decodeReadRequest(ReadKind.Assurance, newSeq[byte](96)).error == ReadError.InvalidRequest
  assert decodeReadRequest(ReadKind.Assurance, newSeq[byte](140)).error == ReadError.LimitExceeded
  for size in [97, 139]:
    # Exact raw upload and both FINs are transport completion only, not an accepted credential.
    let assurance = newSeq[byte](size)
    exchangeClient(ReadKind.Assurance, assurance, @[], holdFin = true, maximum = ByteLimit(0), budget = 0)
  exchangeClient(ReadKind.Assurance, newSeq[byte](97), @[0'u8], maximum = ByteLimit(0),
      failure = ReadError.InvalidRequest)
  for size in [0, 131, 133, 16*133]:
    # Every bounded CE144 batch, including empty transport input, waits for both FINs; managed proof checking grants acceptance separately.
    exchangeClient(ReadKind.AuditAnnouncement, newSeq[byte](size), @[], holdFin = true,
        maximum = ByteLimit(0), budget = 0)
  assert decodeReadRequest(ReadKind.AuditAnnouncement, newSeq[byte](16*133+1)).error ==
      ReadError.LimitExceeded, "audit upload hard ceiling precedes allocation"
  exchangeClient(ReadKind.AuditAnnouncement, newSeq[byte](131), @[0'u8], maximum = ByteLimit(0),
      failure = ReadError.InvalidRequest)
  let blockPayload = newSeq[byte](37)
  let blockRequest = decodeReadRequest(ReadKind.Blocks, blockPayload).value
  assert route.configure(blockRequest, ByteLimit(3)) == ReadError.LimitExceeded
  assert route.bindStream(NativeStream(nil)) == ReadError.InvalidStream
  let largeRequest = decodeReadRequest(ReadKind.Bundle, newSeq[byte](32)).value
  var largeRoute = default(ReadClientRoute)
  assert largeRoute.configure(largeRequest, ByteLimit(16*1024*1024)) == ReadError.None
  assert route.configure(blockRequest, ByteLimit(16*1024*1024)) == ReadError.LimitExceeded
  let shardPayload = newSeq[byte](34)
  let threeFrames = @[0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  exchangeClient(ReadKind.Availability, shardPayload, threeFrames, holdFin = true)
  exchangeClient(ReadKind.Audit, shardPayload, @[0'u8, 0, 0, 0, 0, 0, 0, 0], holdFin = true)
  exchangeClient(ReadKind.Bundle, newSeq[byte](32), @[3'u8, 0, 0, 0, 4, 5, 6], holdFin = true)
  exchangeClient(ReadKind.Blocks, blockPayload, @[0'u8, 0, 0, 0], holdFin = true,
    maximum = ByteLimit(4), budget = 4)
  exchangeClient(ReadKind.Preimage, newSeq[byte](32), @[3'u8, 0, 0, 0, 1, 2, 3])
  exchangeClient(ReadKind.Report, newSeq[byte](32), @[3'u8, 0, 0, 0, 4, 5, 6], holdFin = true)
  var shardBatch = newSeq[byte](34)
  shardBatch.add(1)
  shardBatch.add(0)
  shardBatch.add(0)
  exchangeClient(ReadKind.SegmentShards, shardBatch, @[0'u8, 0, 0, 0])
  exchangeClient(ReadKind.ProvenSegmentShards, shardBatch, @[0'u8, 0, 0, 0, 0, 0, 0, 0],
      holdFin = true)
  var originalBatch = newSeq[byte](32)
  originalBatch.add(1)
  originalBatch.add(0)
  originalBatch.add(0)
  exchangeClient(ReadKind.Segments, originalBatch, @[0'u8, 0, 0, 0, 0, 0, 0, 0], holdFin = true)
  let statePayload = newSeq[byte](98)
  let twoFrames = @[3'u8, 0, 0, 0, 7, 8, 9, 0, 0, 0, 0]
  exchangeClient(ReadKind.State, statePayload, twoFrames, holdFin = true)
  for length in 0..<twoFrames.len:
    var prefix: seq[byte] = @[]
    for index in 0..<length: prefix.add(twoFrames[index])
    exchangeClient(ReadKind.State, statePayload, prefix, failure = ReadError.InvalidRequest)
  exchangeClient(ReadKind.Blocks, blockPayload, @[0'u8, 0, 0, 0, 255],
      failure = ReadError.InvalidRequest)
  exchangeClient(ReadKind.Blocks, blockPayload, @[0'u8, 0, 0, 0, 0, 0, 0, 0],
      failure = ReadError.InvalidRequest)
  exchangeClient(ReadKind.State, statePayload, @[0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      failure = ReadError.InvalidRequest)
  exchangeClient(ReadKind.Blocks, blockPayload, @[255'u8, 255, 255, 255],
      failure = ReadError.LimitExceeded)
  exchangeClient(ReadKind.Blocks, blockPayload, @[2'u8, 0, 0, 0, 1, 2],
    maximum = ByteLimit(4), failure = ReadError.LimitExceeded)
  exchangeClient(ReadKind.Blocks, blockPayload, @[0'u8, 0, 0, 0], budget = 3,
    failure = ReadError.LimitExceeded)
  echo "jamnp read client: exact untrusted replies survive native close"
try:
  main()
except:
  quit 2 # Setup exceptions cannot satisfy a client framing verdict.
