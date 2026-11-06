# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit test-only client verification policy and literal whole-state request construction.
import std/assertions
import ../../src/jamnp-s/[read_stream, read_validation]
import ../../src/chain/genesis
import ../../src/codec/[bounded, header, assurances, tickets, composite, block_codec]
proc readVerificationLimits*(cores = 4, validators = 12, epoch = 12): ReadVerificationLimits =
  ## Structural geometry is caller-selected; trusted-root state verification uses independent full-map work ceilings.
  let maximum = ByteLimit(8388608)
  ReadVerificationLimits(wireBytes: maximum, blocks: ElementLimit(64), map: genesisStoreLimits().trie,
    frame: FrameConfig(cores: CoreCount(uint64(cores)), validators: ValidatorCount(uint64(
        validators)),
      epochSlots: EpochSlots(uint64(epoch)), ticketLimit: TicketLimit(16), maxBytes: maximum,
      preimages: PreimageLimits(items: ElementLimit(8), perBlob: maximum, totalBlobBytes: maximum)))
proc readStateRequest*(hash: BlockHash): ReadRequest =
  ## Whole-keyspace bounds and8MiB protocol maximum are independent literal fixed request bytes.
  var payload: seq[byte] = @[]
  for octet in array[32, byte](hash): payload.add(octet)
  for index in 0..<31: payload.add(0)
  for index in 0..<31: payload.add(255)
  for octet in [0'u8, 0, 128, 0]: payload.add(octet)
  let decoded = decodeReadRequest(ReadKind.State, payload)
  assert decoded.error == ReadError.None
  decoded.value
