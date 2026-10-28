# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supplementary scope retention, fixed-copy independence and result/owner/index guards for
## output logs.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/syncio
import ../../../src/codec/state_outputs as codec_state_outputs
import ../../../src/codec/bounded as codec_bounded

## Capture an immutable sequence that survives local source/wire scope and all later caller mutation.
proc captured(config: OutputLogConfig): OutputLogSnapshot =
  var bytes = default(array[32, byte])
  bytes[0] = 17
  bytes[31] = 255
  var values = @[AccumulationOutput(service: ServiceIndex(high(uint32)),
      commitment: OutputCommitment(bytes)),
    AccumulationOutput(service: ServiceIndex(1), commitment: OutputCommitment(bytes))]
  let encoded = outputLogEntry(values, config)
  assert encoded.error == OutputLogError.None and array[31, byte](encoded.value.key)[0] == 16
  values[0] = default(AccumulationOutput)
  assert encoded.value.value[1] == 255 and encoded.value.value[5] == 17
  var wire = encoded.value.value
  let parsed = decodeOutputLog(wire, config)
  assert parsed.error == OutputLogError.None and parsed.value.consumed == wire.len
  result = parsed.value.snapshot
  for i in 0..<wire.len: wire[i] = 0 # All retained pairs must be independent copies.

## Exercise sequence-order preservation and fixed extraction copies through only public owner operations.
proc main() =
  assert sizeof(int) == 8 and sizeof(AccumulationOutput) == 36
  let config = OutputLogConfig(items: ElementLimit(2), maxBytes: ByteLimit(73))
  let owner = captured(config)
  assert outputLogCount(owner).value == 2
  var first = outputLogAt(owner, OutputLogIndex(0)).value
  assert uint32(first.service) == high(uint32) and array[32, byte](first.commitment)[0] == 17
  assert uint32(outputLogAt(owner, OutputLogIndex(1)).value.service) == 1
  first.service = ServiceIndex(0)
  first.commitment = default(OutputCommitment)
  assert array[32, byte](outputLogAt(owner, OutputLogIndex(0)).value.commitment)[31] == 255
  var replaced = owner
  replaced = default(OutputLogSnapshot)
  assert outputLogCount(owner).value == 2
  let invalid = outputLogAt(owner, OutputLogIndex(high(uint64)))
  assert invalid.error == OutputLogError.InvalidIndex
  let empty = decodeOutputLog(@[0'u8], OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))
  assert empty.error == OutputLogError.None and outputLogCount(empty.value.snapshot).value == 0
  let late = decodeOutputLog(@[2'u8], config)
  assert late.error == OutputLogError.Truncated
  let limited = decodeOutputLog(@[0'u8], OutputLogConfig(items: ElementLimit(0),
      maxBytes: ByteLimit(0)))
  assert limited.error == OutputLogError.LimitExceeded
  echo "PASS output log: scope retention, ordered pairs, independent fixed copies and result/index guards"

main()
