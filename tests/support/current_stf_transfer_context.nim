# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal transfer guests exercise actual terminal selection and recipient re-entry.
import ./pvm_accumulation_program

proc transferCode*(mode: int): seq[byte] =
  ## Modes5..9 select halt, panic, checkpoint-panic, zero amount and a below-minimum offer.
  let amount = if mode == 8: 0'u64 else: 7'u64
  let gas = if mode == 9: 9'u64 else: 10000'u64
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 42),
    registerImmediate(9, 0), registerImmediate(10, amount), registerImmediate(11, gas),
    registerImmediate(12, 196608), @[10'u8, 22]]
  if mode == 7: instructions.add(@[10'u8, 19]) # A real checkpoint retains debit and outgoing transfer on panic.
  instructions.add(if mode in [6, 7]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = newSeq[byte](128)): result.add(octet)
