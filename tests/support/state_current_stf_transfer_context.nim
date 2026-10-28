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

proc forwardingCode*(mode: int): seq[byte] =
  ## A funded incoming memo causes one forward; the original sender cannot afford another outgoing offer.
  let amount = if mode == 19: 0'u64 else: 3'u64
  let gas = if mode == 18: 0'u64 else: 1000'u64
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 99),
    registerImmediate(9, 0), registerImmediate(10, amount), registerImmediate(11, gas),
    registerImmediate(12, 196608), @[10'u8, 22]]
  if mode == 17: instructions.add(@[10'u8, 19]) # Actual checkpoint retains the forwarded debit and outgoing record.
  instructions.add(if mode in [16, 17]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = newSeq[byte](128)): result.add(octet)

proc poolTransferCode*(mode: int): seq[byte] =
  ## Four independent source/destination pool combinations run with a real memo or direct-credit sentinel.
  let selection = uint64((mode-20) mod 4)
  let memo = if mode >= 24: 0'u64 else: 196608'u64
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 42),
    registerImmediate(9, selection), registerImmediate(10, 7), registerImmediate(11, 10000),
    registerImmediate(12, memo), @[10'u8, 22], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = newSeq[byte](128)): result.add(octet)

proc admissionTransferCode*(mode: int): seq[byte] =
  ## Distinct invalid endpoints, authorization/funding/memo checks and exact gas boundaries reach real host dispatch.
  var source = high(uint64)
  var destination = 42'u64
  var selection = 0'u64
  var amount = 7'u64
  var gas = 10000'u64
  var memo = 196608'u64
  case mode
  of 28: source = 77 # An absent source refuses without fabricating a source account.
  of 29: destination = 77 # An absent destination cannot receive or dispatch.
  of 30: source = 42 # The caller does not supervise this existing unfunded source.
  of 31: amount = 1000001 # Selected source funding is one token short.
  of 32: selection = 4 # Undefined pool flags cannot mask into a valid pool.
  of 33: memo = high(uint64)-63 # The fixed128-byte memo extent crosses the register address domain.
  of 34: gas = 9 # Below the recipient's explicit minimum10.
  of 35: gas = 10 # Accepted credit but insufficient to prepay the recipient's22-gas block.
  of 36: gas = 99322 # Exact remaining report budget after instruction and base-host costs.
  of 37: gas = 99323 # The same outgoing host quote is unaffordable by one unit.
  of 38: gas = 21 # Incoming execution is one unit below a whole basic block.
  of 39: gas = 22 # Incoming execution can pay exactly one complete halt block.
  of 40: source = 4294967395'u64 # Full-width source must not alias existing low32 bits99.
  of 41: destination = 4294967338'u64 # Full-width destination must not alias existing low32 bits42.
  else: discard # Only explicit canonical fixture modes reach this family through the driver.
  let instructions = @[registerImmediate(7, source), registerImmediate(8, destination),
    registerImmediate(9, selection), registerImmediate(10, amount), registerImmediate(11, gas),
    registerImmediate(12, memo), @[10'u8, 22], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = newSeq[byte](128)): result.add(octet)

proc memoSenderCode*(): seq[byte] =
  ## Every memo octet has a distinct literal value, so encoding/truncation changes affect the recipient's committed state.
  var memory = newSeq[byte](128)
  for index in 0..<128: memory[index] = byte(index)
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 42),
    registerImmediate(9, 0), registerImmediate(10, 7), registerImmediate(11, 10000),
    registerImmediate(12, 196608), @[10'u8, 22], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc memoReceiverCode*(mode: int): seq[byte] =
  ## Fetch real incoming bytes into initialized RAM, store/yield exactly32 bytes, then select regular or checkpoint effects.
  var memory = newSeq[byte](64)
  for index in 0..<32: memory[index] = 170 # A clamped copy must retain the untouched tail of its destination buffer.
  memory[32] = 7
  let offset = if mode == 46: 131'u64 elif mode == 43: 18'u64 else: 19'u64
  var instructions = @[registerImmediate(7, 196608), registerImmediate(8, offset),
    registerImmediate(9, 32), registerImmediate(10, (if mode == 43: 15'u64 else: 14'u64)),
    registerImmediate(11, 0), @[10'u8, 2], registerImmediate(7, high(uint64)),
    registerImmediate(8, 196640), registerImmediate(9, 1), registerImmediate(10, 196608),
    registerImmediate(11, 32), @[10'u8, 5], registerImmediate(7, 196608), @[10'u8, 27]]
  if mode == 45: instructions.add(@[10'u8, 19]) # Exceptional selection retains the genuinely fetched write/yield prefix.
  instructions.add(if mode in [44, 45]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)
