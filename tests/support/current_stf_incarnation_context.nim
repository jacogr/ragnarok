# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal programs retire/recreate an actual old supervisor before testing incarnation-bound authority on later reports.
import ./pvm_accumulation_program

proc incarnationRebindCode*(mode: int): seq[byte] =
  ## Service42 explicitly rebinds to the newly created77; panic/checkpoint selection preserves the actual old/new creation slot.
  var instructions: seq[seq[byte]] = @[]
  if mode != 171:
    instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 77), @[10'u8,
        29]] # Stale mode never requests a rebind.
  if mode == 174: instructions.add(@[10'u8, 19]) # Capture the new supervisor incarnation before panic.
  instructions.add(if mode in [173, 174]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[]): result.add(octet)

proc incarnationCreatorCode*(mode: int, hash: array[32, byte], child: seq[byte]): seq[byte] =
  ## Eject the real old empty77, recreate that reserved ID and supply its exact foreign-write code in one selected invocation.
  var memory = newSeq[byte](60)
  for index, octet in hash: memory[index] = octet
  let length = uint32(child.len)
  for index in 0..<4: memory[32+index] = byte((length shr (8*index)) and 255)
  memory[36] = 100
  memory[44] = 19
  for octet in child: memory.add(octet)
  let instructions = @[registerImmediate(7, 77), @[10'u8, 23], registerImmediate(7, high(uint64)),
      registerImmediate(8, 77),
    registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20], registerImmediate(7, 77),
    registerImmediate(8, 196668), registerImmediate(9, uint64(child.len)), @[10'u8, 28], (if mode ==
        175: @[0'u8] else: @[50'u8, 0])]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)
