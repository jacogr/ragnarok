# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original inner programs and literal E8 frame fixtures shared by invocation unit and strict misuse probes.

import std/assertions
import ../../src/pvm/inner_machines as pvm_inner_machines
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/program as pvm_program
import ./pvm_inner_lifecycle

proc invokeBlob*(instructions: openArray[seq[byte]]): seq[byte] =
  ## Independently frame short instruction bytes and their exact start-bit mask without production encoders.
  var code: seq[byte] = @[]
  var starts: seq[bool] = @[]
  for instruction in instructions:
    for index, octet in instruction:
      code.add(octet)
      starts.add(index == 0)
  assert code.len > 0 and code.len < 128
  result = @[0'u8, 0, byte(code.len)]
  for octet in code: result.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index, marked in starts:
    if marked: mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: result.add(octet)
proc invokeRegisters*(): RegisterFile =
  ## Thirteen literal full-width patterns expose dropped bytes, wrong offsets or accidental register replacement.
  result = default(RegisterFile)
  for index in 0..<13: result[index] = RegisterValue(0x1020304050607000'u64+uint64(index))
  result[0] = RegisterValue(0xffff0000'u64) # The guest's jump_ind r0 reaches the real halt sentinel.
proc invokeMemory*(blob = innerBlob(), fuel = 100'u64, regs = invokeRegisters(),
    address = 196608'u64): Memory =
  ## Copy one RO program page and two sentinel RW pages, placing all 112 frame bytes independently.
  assert blob.len <= 4096 and address >= 196608 and address <= 204800'u64-112
  var code = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
  for index, octet in blob: code.bytes[index] = octet
  var first = PageImage(index: PageIndex(48), access: PageAccess.ReadWrite)
  var second = PageImage(index: PageIndex(49), access: PageAccess.ReadWrite)
  for index in 0..<4096:
    first.bytes[index] = 173
    second.bytes[index] = 173 # Frame writes must retain outside bytes, including a cross-page suffix.
  for word in 0..<14:
    let value = if word == 0: fuel else: uint64(regs[word-1])
    for octet in 0..<8:
      let offset = int(address-196608)+word*8+octet
      let byteValue = byte((value shr (octet*8)) and 255)
      if offset < 4096: first.bytes[offset] = byteValue
      else: second.bytes[offset-4096] = byteValue
  captureMemory([code, first, second], PageLimit(3)).value
proc invokeMachines*(blob = innerBlob(), cap = innerLimits()): InnerMachines =
  ## Only real machine creation authorizes program/PC/RAM ownership; frames cannot substitute it later.
  let memory = invokeMemory(blob)
  let created = preparedInnerMachine(captureInnerMachines(cap), MachineGas(100000),
    innerRegisters(uint64(blob.len)), memory).value
  created.machines

proc invokeArgs*(id = 0'u64, address = 196608'u64): RegisterFile =
  ## Outer argument registers are distinct from the thirteen inner words in caller memory.
  result = innerRegisters()
  result[7] = RegisterValue(id)
  result[8] = RegisterValue(address)
proc invokeFrame*(memory: Memory, address = 196608'u64): array[14, uint64] =
  ## Decode frame bytes independently for literal endian/word-position witnesses, never through the implementation helper.
  result = default(array[14, uint64])
  let bytes = memory.readBytes(MemoryAddress(address), MemoryLength(112), MemoryByteLimit(112)).value
  for word in 0..<14:
    for octet in 0..<8: result[word] = result[word] or (uint64(bytes[word*8+octet]) shl (octet*8))
