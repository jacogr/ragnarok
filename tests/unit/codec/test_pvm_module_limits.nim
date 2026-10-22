# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The current paper and PolkaVM share exact module code, jump-count and width limits.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, initialize, inner_machines, step]
import ../../support/pvm_inner_lifecycle

for row in [(@[224'u8, 255, 255, 255], 16777215'u64),
    (@[225'u8, 0, 0, 0], 16777216'u64), (@[225'u8, 1, 0, 0], 16777217'u64),
    (@[255'u8, 255, 255, 255, 255, 255, 255, 255, 255], high(uint64))]:
  # Independent canonical natural headers encode the declared count; E_0 needs no table bytes.
  var wire = row[0]
  for octet in [0'u8, 1, 0, 1]: wire.add(octet)
  let raw = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(high(uint64)))
  assert raw.error == (if row[1] <= 16777216: ProgramError.None else: ProgramError.InvalidProgram)
  if row[1] <= 16777216: assert uint64(jumpTarget(raw.value, JumpIndex(row[1]-1)).value) == 0
  let jam = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(high(uint64)))
  let accepted = row[1] <= 16777216'u64
  assert jam.error == (if accepted: ProgramError.None else: ProgramError.InvalidProgram)
  if accepted: assert jumpTarget(jam.value, JumpIndex(0)).error == ProgramError.InvalidIndex
  let local = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(row[1]-1))
  assert local.error == ProgramError.LimitExceeded
  var envelope = newSeq[byte](15)
  envelope[11] = byte(wire.len)
  for octet in wire: envelope.add(octet)
  let limits = InitializationLimits(envelope: InitializationByteLimit(64),
      program: ProgramByteLimit(64),
    jumps: JumpCountLimit(high(uint64)), pages: PageLimit(0))
  let initialized = initializeMachine(envelope, [], CodeAddress(0), MachineGas(0), limits)
  assert initialized.error == (if accepted: InitializationError.None else: InitializationError.InvalidProgram)
  var innerPolicy = innerLimits()
  innerPolicy.jumps = JumpCountLimit(high(uint64))
  let empty = captureInnerMachines(innerPolicy)
  let created = preparedInnerMachine(empty, MachineGas(10000), innerRegisters(uint64(wire.len)),
      innerMemory(wire)).value
  assert created.response.action == HostAction.Continue
  assert uint64(created.response.registers[7]) == (if accepted: 0'u64 else: high(uint64)-8)
  assert created.machines.innerMachineCount.value == uint32(accepted)
  assert empty.innerMachineCount.value == 0

for row in [(33554431, [225'u8, 255, 255, 255]), (33554432, [226'u8, 0, 0, 0]),
    (33554433, [226'u8, 1, 0, 0])]:
  # Full present trap code proves acceptance at both exact fitting edges, not merely truncated-header parsing.
  let size = row[0]
  var wire = @[0'u8, 0]
  for octet in row[1]: wire.add(octet)
  wire.setLen(6+size+(size+7) div 8)
  for index in (6+size)..<wire.len: wire[index] = 255
  if size mod 8 != 0: wire[wire.len-1] = byte((1 shl (size mod 8))-1)
  let raw = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(40000000), JumpCountLimit(0))
  assert raw.error == (if size <= 33554432: ProgramError.None else: ProgramError.InvalidProgram)
  if size <= 33554432: assert raw.value.codeLength.value == uint64(size)
  let jam = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(40000000), JumpCountLimit(0))
  assert jam.error == (if size <= 33554432: ProgramError.None else: ProgramError.InvalidProgram)
  if size <= 33554432: assert jam.value.codeLength.value == uint64(size)

echo "PVM module-limit compatibility passed: 7"
