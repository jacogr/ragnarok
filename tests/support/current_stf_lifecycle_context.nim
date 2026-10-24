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

proc supervisorCode*(mode: int): seq[byte] =
  ## Reassign self supervision before attempting a protected-pool deferred transfer, making lost authority observable.
  let nominee = if mode == 53: high(uint64) elif mode == 54: 77'u64 else: 42'u64
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, nominee), @[10'u8, 29]]
  if mode == 56: instructions.add(@[10'u8, 19]) # Capture the changed supervisor before the later protected-transfer attempt.
  for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 42),
      registerImmediate(9, 1), registerImmediate(10, 7), registerImmediate(11, 10000),
      registerImmediate(12, 196608), @[10'u8, 22]]:
    instructions.add(instruction) # Every transfer reads the actual earlier supervisor mutation in this invocation.
  instructions.add(if mode in [55, 56]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = newSeq[byte](128)): result.add(octet)
