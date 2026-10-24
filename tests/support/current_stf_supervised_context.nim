# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal foreign-account programs exercise authority and selected publication through genuine current guests.
import ./pvm_accumulation_program

proc supervisedWriteCode*(mode: int): seq[byte] =
  ## Target42 receives a distinct raw storage key; later current account selection must publish only the selected context.
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, 196608), registerImmediate(9, 1),
    registerImmediate(10, 196609), registerImmediate(11, 3), @[10'u8, 5]]
  if mode == 84: instructions.add(@[10'u8, 19]) # Retain the exact foreign write before exceptional termination.
  instructions.add(if mode in [83, 84]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[7'u8, 9, 8, 7]): result.add(octet)
