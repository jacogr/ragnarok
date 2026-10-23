# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent exact CE128 request order and E4 historical framing qualify remote lookup after an actual predecessor.
import std/assertions
import ../../src/chain/genesis
import ../../src/codec/header
import ./[current_guarantee_sequence_context, current_consecutive_download_context,
  current_download_command_context, accumulation_current_chain_context]

proc currentHistoricalFrame*(fixture: CurrentGuaranteeSequenceFixture, wrong = false): seq[byte] =
  ## An original sealed header plus framed empty extrinsics supplies ancestry only, never a historical state-transition certificate.
  assert fixture.sequence.seed.older.len == 1
  var body = currentChainBytes(fixture.sequence.seed.older[0])
  if wrong: body[body.high] = body[body.high] xor 1 # Same syntax/extent cannot substitute another sealed identity.
  for index in 0..<7: body.add(0'u8)
  result = newSeq[byte](body.len+4)
  for index in 0..<4: result[index] = byte((uint64(body.len) shr (8*index)) and 255)
  for index, octet in body: result[index+4] = octet

proc currentGuaranteeRequests*(fixture: CurrentGuaranteeSequenceFixture): seq[array[42, byte]] =
  ## Two ascending current requests precede one descending original ancestor request from the retained initial header's parent.
  result = @[currentExpectedRequest(array[32, byte](fixture.sequence.heads[0].blockHash)),
    currentExpectedRequest(array[32, byte](fixture.sequence.heads[1].blockHash))]
  var ancestor = currentExpectedRequest(array[32, byte](
      fixture.sequence.seed.parent.value.header.headerInfo.value.unsigned.parent))
  ancestor[37] = 1
  result.add(ancestor)

proc currentGuaranteeResponses*(fixture: CurrentGuaranteeSequenceFixture, wrong = false): seq[seq[byte]] =
  ## Frames retain the original current bodies and exact historical context independently of receiver/controller implementation.
  @[currentConsecutiveResponse(fixture.sequence.children[0]),
    currentConsecutiveResponse(fixture.sequence.children[1]), currentHistoricalFrame(fixture, wrong)]
