# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored test-only program assembly for accumulation dispatch and outcome witnesses.
## Exposes guestProgram and registerImmediate; no production execution or verdict is replaced.

import std/assertions
import ../../src/state/accumulation_machine
import ../../src/pvm/[initialize, machine, program]
import ./pvm_accumulation_context
import ../../src/codec/[state_trie, state_accounts]

proc guestProgram*(instructions: openArray[seq[byte]], credit = 10000'u64,
    includeContexts = true, extra: seq[StateEntry] = @[], account = default(ServiceMetadata),
        spareEntries = 0): PreparedAccumulationMachine =
  ## Assemble authored instruction sequences at the fixed entry; mask bits mark exact opcode bytes.
  ## No upstream assembler runs, and each single-byte code count is proven before narrowing.
  ## Forward account metadata and explicit spare map capacity to the authentic bootstrap fixture.
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[true, true, true, true, true]
  for instruction in instructions:
    # Borrow each complete authored instruction; arguments are never marked as opcodes.
    assert instruction.len > 0
    for i, octet in instruction:
      code.add(octet)
      starts.add(i == 0)
  assert code.len < 128
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code:
    raw.add(octet) # Instruction data precedes the packed LSB-first bitmask.
  var mask = newSeq[byte]((code.len+7) div 8)
  for i, marked in starts:
    if marked:
      mask[i div 8] = mask[i div 8] or byte(1 shl (i mod 8)) # Only true opcode positions are set.
  for octet in mask:
    raw.add(octet) # Padding bits remain canonical zero.
  initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(raw), credit,
    includeContexts = includeContexts, extra = extra, account = account,
        spareEntries = spareEntries),
    InitializationLimits(envelope: InitializationByteLimit(256), program: ProgramByteLimit(128),
      jumps: JumpCountLimit(0), pages: PageLimit(5))).value

proc registerImmediate*(index: byte, address: uint64): seq[byte] =
  ## Load a full 64-bit pointer; extended immediates avoid sign-extension aliases in address witnesses.
  result = @[20'u8, index]
  for i in 0..<8:
    result.add(byte((address shr (8*i)) and 255)) # Independent LE encoding at every register bit.

