# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal foreign-funded creation and parallel junior self-write inputs for independently calculated N/M selection cases.
import ./pvm_accumulation_program

proc foreignFundingJuniorCode*(): seq[byte] =
  ## The participating source42 writes one raw byte before modified-account conflict selection.
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1),
    registerImmediate(10, 196609), registerImmediate(11, 1), @[10'u8, 5], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[7'u8, 42]): result.add(octet)

proc foreignCreationCode*(mode: int, hash: array[32, byte], length: uint32): seq[byte] =
  ## Registrar99 selects actual supervised42 funding, rather than borrowing from its own funded account.
  var memory = newSeq[byte](60)
  for index, octet in hash: memory[index] = octet
  for index in 0..<4: memory[32+index] = byte((length shr (8*index)) and 255)
  memory[36] = 100
  memory[44] = 19
  let pool = uint64(if mode <= 179: mode-176 else: 0)
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, 77), registerImmediate(9,
      pool), registerImmediate(10, 196608), @[10'u8, 20]]
  if mode == 182: instructions.add(@[10'u8, 19]) # Retain foreign debit, child credit and conflict membership as one implication.
  instructions.add(if mode in [181, 182]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc foreignDirectTransferCode*(mode: int): seq[byte] =
  ## Explicit zero memo pointer selects direct transfer from supervised42 into invoking99, including protected pool choices.
  let pool = uint64(if mode <= 186: mode-183 else: 0)
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, 99), registerImmediate(9, pool),
    registerImmediate(10, 7), registerImmediate(11, 0), registerImmediate(12, 0), @[10'u8, 22]]
  if mode == 189: instructions.add(@[10'u8, 19]) # Retain both endpoint balances before panic.
  instructions.add(if mode in [188, 189]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[]): result.add(octet)
