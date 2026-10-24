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

proc creationCode*(mode: int, replacement: array[32, byte], codeLength: uint32): seq[byte] =
  ## Real new20 reads the complete current60-byte request; a repeated call advances the genuine public cursor.
  var memory = newSeq[byte](60)
  for index, octet in replacement: memory[index] = octet
  let length = if mode == 61: high(uint32)-1 else: codeLength
  for index in 0..<4: memory[32+index] = byte((length shr (8*index)) and 255)
  memory[36] = 100
  memory[44] = 19
  var instructions: seq[seq[byte]] = @[]
  for call in 0..(if mode == 60: 1 else: 0):
    # Reset the source sentinel after each returned child ID; all other arguments are explicit too.
    for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
        registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20]]:
      instructions.add(instruction)
  if mode == 59: instructions.add(@[10'u8, 19]) # Keep the actual created account/request/cursor in the exceptional implication.
  instructions.add(if mode in [58, 59]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc requestCode*(mode: int, hash: array[32, byte]): seq[byte] =
  ## Solicit/forget a single declared identity; checkpoints distinguish removal from a later discarded recreation.
  var memory = newSeq[byte](32)
  for index, octet in hash: memory[index] = octet
  var operations = @[25'u8]
  case mode
  of 63: operations = @[25'u8, 26] # Ordinary creation and removal restore the original request footprint.
  of 64: operations = @[26'u8, 19, 25] # Select the removed request before discarding a later recreation.
  of 66: operations = @[25'u8, 19] # Retain a genuine pending request after exceptional termination.
  else: discard # Single-call halt/panic modes share the same literal solicitation.
  var instructions: seq[seq[byte]] = @[]
  for operation in operations:
    if operation == 19:
      instructions.add(@[10'u8, 19]) # Capture the actual preceding request namespace version.
    else:
      for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
          registerImmediate(9, 1), @[10'u8, operation]]:
        instructions.add(instruction) # Every call reselects self after the previous protocol return code.
  instructions.add(if mode in [64, 65, 66]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc provisionCode*(mode: int, hash: array[32, byte]): seq[byte] =
  ## Provide a single explicit R payload and exercise account changes before the final relevance filter.
  var memory = newSeq[byte](33)
  for index, octet in hash: memory[index] = octet
  memory[32] = 82
  var operations = @[28'u8]
  case mode
  of 69: operations = @[28'u8, 19] # Exceptional selection retains the queued pair.
  of 70: operations = @[26'u8, 28] # A removed request cannot authorize a later provision.
  of 71: operations = @[28'u8, 26] # A queued pair becomes irrelevant after selected removal.
  else: discard # Ordinary and panic provision literals share the same host call.
  var instructions: seq[seq[byte]] = @[]
  for operation in operations:
    if operation == 19:
      instructions.add(@[10'u8, 19]) # Retain the actual queued pair before exceptional termination.
    else:
      let pointer = if operation == 26: 196608'u64 else: 196640'u64
      for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, pointer),
          registerImmediate(9, 1), @[10'u8, operation]]:
        instructions.add(instruction) # Reset self and the correct hash/payload address after every status.
  instructions.add(if mode in [68, 69]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc ejectionCode*(mode: int): seq[byte] =
  ## Retire a declared empty old junior and make the selected two-pool liquid refund visible in the full map.
  let target = if mode == 76: 88'u64 else: 77'u64
  var instructions = @[registerImmediate(7, target), @[10'u8, 23]]
  if mode == 74: instructions.add(@[10'u8, 19]) # Deletion and refund belong to the same exceptional implication.
  instructions.add(if mode in [73, 74]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, newSeq[byte](0)): result.add(octet)

proc managerCode*(mode: int): seq[byte] =
  ## One authorized manager hands off the fixed roles with an empty, unambiguous allowance map.
  let manager = if mode == 80: 99'u64 else: 42'u64
  var instructions = @[registerImmediate(7, manager), registerImmediate(8, 196608),
    registerImmediate(9, 0), registerImmediate(10, 0), registerImmediate(11, 196616),
    registerImmediate(12, 0), @[10'u8, 16]]
  if mode == 79: instructions.add(@[10'u8, 19]) # Capture role handoff before exceptional selection.
  instructions.add(registerImmediate(7, 99))
  instructions.add(@[10'u8, 16]) # A second attempt observes the manager already selected by the first host call.
  instructions.add(if mode in [78, 79]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, newSeq[byte](8)): result.add(octet)
