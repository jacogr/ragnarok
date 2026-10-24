# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal nonempty privilege programs for independently calculated current-STF dictionary/scheduling witnesses.
import ./pvm_accumulation_program

proc blessAllowanceCode*(mode: int): seq[byte] =
  ## Distinguish raw table charging from canonical set order and duplicate removal, preserving actual checkpoint selection.
  let pairs = if mode == 159: @[(99'u32, 6000'u64), (42'u32, 100'u64)]
    elif mode == 158: @[(42'u32, 100'u64), (42'u32, 100'u64)] else: @[(42'u32, 100'u64)]
  var memory = newSeq[byte](8)
  for pair in pairs:
    # Independent raw E4/E8 bytes preserve the supplied ordinal before the host canonicalizes its set.
    for index in 0..<4: memory.add(byte((pair[0] shr (8*index)) and 255))
    for index in 0..<8: memory.add(byte((pair[1] shr (8*index)) and 255))
  var instructions = @[registerImmediate(7, 99), registerImmediate(8, 196608), registerImmediate(9, 0),
    registerImmediate(10, 0), registerImmediate(11, 196616), registerImmediate(12, uint64(
        pairs.len)), @[10'u8, 16]]
  if mode == 157: instructions.add(@[10'u8, 19]) # Keep this exact nonempty dictionary in the exceptional implication.
  instructions.add(if mode in [156, 157]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)
