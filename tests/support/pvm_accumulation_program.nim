# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored test-only program assembly for accumulation dispatch and outcome witnesses.
## Exposes guestEnvelope, guestProgram and registerImmediate; no production execution or verdict is replaced.

import std/assertions
import ../../src/state/accumulation_machine as state_accumulation_machine
import ../../src/pvm/initialize as pvm_initialize
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/program as pvm_program
import ./pvm_accumulation_context
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/header as codec_header

proc guestEnvelope*(instructions: openArray[seq[byte]], writable: seq[byte] = @[81'u8]): seq[byte] =
  ## Copy authored instructions into the bounded entry-5 envelope; exact opcode masks and framing match guestProgram.
  ## Code remains below 192 bytes; independently framed one/two-byte lengths cover current account-selector guests.
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[true, true, true, true, true]
  for instruction in instructions:
    # Borrow each complete authored instruction; arguments are never marked as opcodes.
    assert instruction.len > 0
    for i, octet in instruction:
      code.add(octet)
      starts.add(i == 0)
  assert code.len < 192
  var raw = @[0'u8, 0]
  if code.len < 128:
    raw.add(byte(code.len)) # One-byte canonical natural preserves all earlier small guests.
  else:
    raw.add(128'u8)
    raw.add(byte(code.len)) # For 128..191 the canonical natural is prefix128 followed by the low byte.
  for octet in code:
    raw.add(octet) # Instruction data precedes the packed LSB-first bitmask.
  var mask = newSeq[byte]((code.len+7) div 8)
  for i, marked in starts:
    if marked:
      mask[i div 8] = mask[i div 8] or byte(1 shl (i mod 8)) # Only true opcode positions are set.
  for octet in mask:
    raw.add(octet) # Padding bits remain canonical zero.
  pvmEnvelope(raw, writable)

proc guestProgram*(instructions: openArray[seq[byte]], credit = 10000'u64,
    includeContexts = true, extra: seq[StateEntry] = @[], account = default(ServiceMetadata),
        spareEntries = 0, manager = 0'u32, assigner = 0'u32, delegator = 0'u32, registrar = 0'u32,
            cores = 2'u64, writes = 2'u64, probes = 1'u64, slot = HeaderSlot(128),

writable: seq[byte] = @[81'u8], service = ServiceIndex(42)): PreparedAccumulationMachine =
  ## Assemble authored instruction sequences at the fixed entry; mask bits mark exact opcode bytes.
  ## No upstream assembler runs; independently framed code lengths are bounded before narrowing.
  ## service selects the nominal invoking identity; the default preserves existing authored programs.
  ## slot forwards the nominal invocation header time; existing callers retain the same default.
  ## Forward initial roles, account metadata, bounded inputs/profile, store/probe policy and spare map capacity.
  ## The 160-byte caller budget includes framing/mask; larger integration guests use explicit initialization profiles.
  initializeAccumulationMachine(pvmBootstrap(guestEnvelope(instructions, writable), credit,
    includeContexts = includeContexts, extra = extra, account = account, serviceId = uint32(
        service), spareEntries = spareEntries, manager = manager, assigner = assigner,
            delegator = delegator, cores = cores, writes = writes, probes = probes,
                registrar = registrar, slot = slot),
    InitializationLimits(envelope: InitializationByteLimit(4096), program: ProgramByteLimit(160),
      jumps: JumpCountLimit(0), pages: PageLimit(5))).value

proc registerImmediate*(index: byte, address: uint64): seq[byte] =
  ## Load a full 64-bit pointer; extended immediates avoid sign-extension aliases in address witnesses.
  result = @[20'u8, index]
  for i in 0..<8:
    result.add(byte((address shr (8*i)) and 255)) # Independent LE encoding at every register bit.

