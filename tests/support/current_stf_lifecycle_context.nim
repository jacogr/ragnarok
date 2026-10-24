# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal lifecycle guests preserve real host calls, terminal selection and subsequent current-code lookup.
import ./pvm_accumulation_program

proc upgradeCode*(mode: int, replacement: array[32, byte]): seq[byte] =
  ## Replace only the invoking account's code hash and minimum gas fields; the target code has an independently declared request.
  var memory = newSeq[byte](32)
  for index, octet in replacement: memory[index] = octet
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
    registerImmediate(9, 100), registerImmediate(10, 19), @[10'u8, 21]]
  if mode == 49: instructions.add(@[10'u8, 19]) # The actual checkpoint retains the selected upgrade on exceptional termination.
  instructions.add(if mode in [48, 49]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)
