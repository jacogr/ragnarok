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

proc supervisedRequestCode*(mode: int, hash: array[32, byte]): seq[byte] =
  ## All reservation/removal arguments name inactive42; its selected supervisor owns the final request facts.
  var memory = newSeq[byte](32)
  for index, octet in hash: memory[index] = octet
  var operations = @[25'u8]
  case mode
  of 88: operations = @[25'u8, 26] # Create and remove the foreign pending reservation in one selected context.
  of 89: operations = @[26'u8, 19, 25] # Checkpoint foreign removal, then discard its ordinary recreation.
  of 91: operations = @[25'u8, 19] # Exceptional selection retains a genuine foreign reservation.
  else: discard # The ordinary and panic variants share literal solicitation.
  var instructions: seq[seq[byte]] = @[]
  for operation in operations:
    if operation == 19:
      instructions.add(@[10'u8, 19]) # Capture the foreign namespace version at this exact point.
    else:
      for instruction in [registerImmediate(7, 42), registerImmediate(8, 196608),
          registerImmediate(9, 1), @[10'u8, operation]]:
        instructions.add(instruction) # Reset the explicit target after every returned status.
  instructions.add(if mode in [89, 90, 91]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc supervisedReplacementCode*(): seq[byte] =
  ## U differs from the original Q code framing while preserving literal halt semantics and exact22 gas.
  result = @[0'u8]
  for octet in guestEnvelope([@[50'u8, 0]], @[85'u8]): result.add(octet)

proc supervisedUpgradeCode*(mode: int, hash: array[32, byte]): seq[byte] =
  ## Upgrade foreign42 through a real host21; namespace availability remains independently declared.
  var memory = newSeq[byte](32)
  for index, octet in hash: memory[index] = octet
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, 196608),
    registerImmediate(9, 100), registerImmediate(10, 19), @[10'u8, 21]]
  if mode == 94: instructions.add(@[10'u8, 19]) # Foreign metadata joins the actual checkpoint implication.
  instructions.add(if mode in [93, 94]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)
