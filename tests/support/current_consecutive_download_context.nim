# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit consecutive current policies and independent signed-block framing serve real command workloads.
import std/assertions
import ../../src/app/candidate
import "../../src/jamnp-s/current/block/download/loop" as current_block_download_loop
import ../../src/codec/[bounded, block_codec]
import ./[current_consecutive_context, current_download_command_context]

proc currentConsecutivePolicy*(): CurrentDownloadLoopLimits =
  ## Preserve every explicit network/whole-attempt ceiling and the bounded consecutive candidate policy.
  result = currentCommandLimits()
  result.candidate = currentConsecutiveLimits()

proc currentConsecutiveResponse*(child: OwnedBlock): seq[byte] =
  ## Independently encode one complete E4-framed signed block; no download receiver or completion certificate is reused.
  let extent = child.blockInfo.value.consumed
  assert extent <= high(int)-4 and uint64(extent) <= 0xffffffff'u64
  var wire = newSeq[byte](extent)
  assert encodeOwnedBlock(child, wire).error == FrameError.None
  result = newSeq[byte](extent+4)
  for index in 0..<4: result[index] = byte((uint64(extent) shr (8*index)) and 255)
  for index, octet in wire: result[index+4] = octet
