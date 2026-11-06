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
  let blockPayload = newSeq[byte](37)
  let blockRequest = decodeReadRequest(ReadKind.Blocks, blockPayload).value
  assert route.configure(blockRequest, ByteLimit(3)) == ReadError.LimitExceeded
  assert route.bindStream(NativeStream(nil)) == ReadError.InvalidStream
  exchangeClient(ReadKind.Blocks, blockPayload, @[0'u8, 0, 0, 0], holdFin = true,
    maximum = ByteLimit(4), budget = 4)
  exchangeClient(ReadKind.Preimage, newSeq[byte](32), @[3'u8, 0, 0, 0, 1, 2, 3])
  exchangeClient(ReadKind.Report, newSeq[byte](32), @[3'u8, 0, 0, 0, 4, 5, 6], holdFin = true)
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
