# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal foreign-account programs exercise authority and selected publication through genuine current guests.
import ./pvm_accumulation_program
import ../../src/crypto/primitives

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

proc juniorConflictCode*(mode: int): seq[byte] =
  ## Self write, yield and provision are independently observable after supervisor conflict selection.
  var memory = newSeq[byte](65)
  memory[0] = 7
  memory[1] = 42
  memory[64] = 73
  for index in 0..<32: memory[32+index] = byte(index)
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
    registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, 1), @[10'u8, 5],
    registerImmediate(7, 196640), @[10'u8, 27], registerImmediate(7, high(uint64)),
    registerImmediate(8, 196672), registerImmediate(9, 1), @[10'u8, 28]]
  instructions.add(if mode == 100: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc supervisorConflictCode*(mode: int): seq[byte] =
  ## Actual selected foreign membership cancels the junior; a discarded uncheckpointed write cannot conflict.
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, 196608),
    registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, 1), @[10'u8, 5]]
  if mode == 99: instructions.add(@[10'u8, 19]) # Preserve genuine foreign membership in the exceptional implication.
  instructions.add(if mode in [98, 99]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[7'u8, 99]): result.add(octet)

proc supervisedHandoffCode*(mode: int): seq[byte] =
  ## Original-role selection must publish a changed foreign supervisor even after this invocation loses write authority.
  let nominee = if mode == 103: 99'u64 elif mode == 104: 77'u64 else: 42'u64
  var instructions = @[registerImmediate(7, 42), registerImmediate(8, nominee), @[10'u8, 29]]
  if mode == 106: instructions.add(@[10'u8, 19]) # Retain the actual role change before exceptional selection.
  for instruction in [registerImmediate(7, 42), registerImmediate(8, 196608), registerImmediate(9,
      1), registerImmediate(10, 196609), registerImmediate(11, 3), @[10'u8, 5]]:
    instructions.add(instruction) # The real second host call sees the earlier selected authority mutation.
  instructions.add(if mode in [105, 106]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, @[7'u8, 9, 8, 7]): result.add(octet)

proc authorizationQueue(): seq[byte] =
  ## Share exact literal positional inputs while every caller owns its copied VM memory.
  result = @[]
  for index in 0..<80:
    var source: seq[byte] = @[] # Keep each positional hash input independent and explicitly ordered.
    for octet in "authorization queue A": source.add(byte(octet))
    source.add(byte(index))
    for octet in array[32, byte](blake2b256(source).value): result.add(octet)

proc authorizationAssignCode*(mode: int): seq[byte] =
  ## Ordered80-hash replacement and handoff run through real host17 with an explicit2560-byte input.
  let memory = authorizationQueue()
  let core = if mode == 110: 2'u64 else: 1'u64
  let nominee = if mode == 111: 4294967338'u64 else: 42'u64
  var instructions = @[registerImmediate(7, core), registerImmediate(8, 196608), registerImmediate(
      9, nominee), @[10'u8, 17]]
  if mode == 109: instructions.add(@[10'u8, 19]) # Queue and assigner join one actual exceptional implication.
  for instruction in [registerImmediate(7, core), registerImmediate(8, 196608),
      registerImmediate(9, if mode == 111: nominee else: 99'u64), @[10'u8, 17]]:
    instructions.add(instruction) # A later host call must observe the current assigner, never its original privilege.
  instructions.add(if mode in [108, 109]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc precedenceAssignerCode*(mode: int): seq[byte] =
  ## The original42 assigner selects its queue even when the manager redirects the posterior role elsewhere.
  var instructions = @[registerImmediate(7, 1), registerImmediate(8, 196608), registerImmediate(9,
      99), @[10'u8, 17]]
  instructions.add(if mode == 117: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, authorizationQueue()): result.add(octet)

proc precedenceManagerCode*(mode: int): seq[byte] =
  ## Empty allowance maps make original-manager versus original-assigner precedence unambiguous under GP R.
  var memory = newSeq[byte](8)
  memory[0] = 42
  if mode == 114: memory[4] = 42 # Keeping the old role defers to the original assigner's own proposal.
  var instructions = @[registerImmediate(7, 99), registerImmediate(8, 196608), registerImmediate(9, 0),
    registerImmediate(10, 0), registerImmediate(11, 196616), registerImmediate(12, 0), @[10'u8, 16]]
  if mode == 116: instructions.add(@[10'u8, 19]) # Retain the manager proposal before exceptional termination.
  instructions.add(if mode in [115, 116]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc designationCode*(mode: int, staging: seq[byte]): seq[byte] =
  ## The exact six-record authored roster is VM input, not a substituted native transition result.
  let count = if mode == 121: 5'u64 else: 6'u64
  var instructions = @[registerImmediate(7, 196608), registerImmediate(8, count), @[10'u8, 18]]
  if mode == 120: instructions.add(@[10'u8, 19]) # Preserve the selected staged roster on exceptional termination.
  instructions.add(if mode in [119, 120]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, staging): result.add(octet)

proc reservedCreationCode*(mode: int, hash: array[32, byte], codeLength: uint32): seq[byte] =
  ## Registrar creation moves real deposits between selected source/child pools and keeps reserved identity stable.
  var memory = newSeq[byte](60)
  for index, octet in hash: memory[index] = octet
  for index in 0..<4: memory[32+index] = byte((codeLength shr (8*index)) and 255)
  memory[36] = 100
  memory[44] = 19
  let selection = if mode in 123..126: uint64(mode-123) else: 0'u64
  let desired = if mode == 129: 42'u64 else: 77'u64
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, desired),
    registerImmediate(9, selection), registerImmediate(10, 196608), @[10'u8, 20]]
  if mode == 128: instructions.add(@[10'u8, 19]) # Debit and born child enter one actual selected implication.
  instructions.add(if mode in [127, 128]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)

proc childReadinessCode*(mode: int, hash: array[32, byte], childCode: seq[byte]): seq[byte] =
  ## Keep the real returned public ID in r6 across checkpoint19, then provide exactly this child's reserved code.
  var memory = newSeq[byte](60)
  for index, octet in hash: memory[index] = octet
  let length = uint32(childCode.len)
  for index in 0..<4: memory[32+index] = byte((length shr (8*index)) and 255)
  memory[36] = 100
  memory[44] = 19
  for octet in childCode: memory.add(octet)
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, high(uint64)),
    registerImmediate(9, 0), registerImmediate(10, 196608), @[10'u8, 20], @[100'u8, 0x76]]
  if mode == 133: instructions.add(@[10'u8, 19]) # Capture a created but not yet provided child.
  for instruction in [@[100'u8, 0x67], registerImmediate(8, 196668), registerImmediate(9, uint64(
      childCode.len))]:
    instructions.add(instruction) # Restore the returned child ID after checkpoint clobbers r7.
  if mode == 135: instructions.add(registerImmediate(7,
      77)) # This nonexistent target must return WHO and leave the child pending.
  instructions.add(@[10'u8, 28])
  if mode == 134: instructions.add(@[10'u8, 19]) # Capture the complete created-account/provision pair before panic.
  instructions.add(if mode in [132, 133, 134]: @[0'u8] else: @[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, memory): result.add(octet)
