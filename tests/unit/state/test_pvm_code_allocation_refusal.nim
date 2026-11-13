# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Valid borrowed wire images exercise actual refused owned copies and source-rank allocations.

import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, step]
import ../../../src/pvm/gas/gas

const
  LargeCode = 1024*1024
  MediumCode = 512*1024
  Header = 5
  Cycles = GasCycleLimit(10000)

proc trapProgram(wire: var openArray[byte], codeLength: int): ProgramResult[Program] =
  ## The caller supplies zeroed backing outside the capped heap. Mark every trap as an instruction.
  let encoded = encode(JamNatural(uint64(codeLength)))
  assert encoded.len == Header-2
  for i in 0..<encoded.len: wire[2+i] = encoded.bytes[i]
  for i in Header+codeLength..<wire.len: wire[i] = 255
  decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(uint64(wire.len)), JumpCountLimit(0))

var large = default(array[Header+LargeCode+LargeCode div 8, byte])
let oversizedCapture = trapProgram(large, LargeCode)
assert oversizedCapture.error == ProgramError.AllocationRefused
assert threadOutOfMem()

var medium = default(array[Header+MediumCode+MediumCode div 8, byte])
let decoded = trapProgram(medium, MediumCode)
assert decoded.error == ProgramError.None
let owner = decoded.value
assert programBytes(owner).error == ProgramError.AllocationRefused
block:
  # Keep the admitted wire and live pressure below 1 MiB. The additional rank
  # payload exceeds the remaining heap. Releasing pressure permits a retry.
  let pressure = newSeq[byte](350*1024)
  assert pressure.len == 350*1024
  let prepared = newPreparedProgram(owner, defaultPreparedLimits(Cycles))
  assert prepared.error == PreparationError.LimitExceeded
  assert pressure[0] == 0
assert newPreparedProgram(owner, defaultPreparedLimits(Cycles)).error == PreparationError.None
assert instructionOpcode(owner, CodeAddress(uint64(MediumCode-1))).value == 0

const Tiny = [0'u8, 0, 1, 0, 1]
let tiny = decodeJamProgram(Tiny, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0)).value

proc checkOwnerRefusal(headroom: int, capture: bool) =
  ## Leave enough space for one or more earlier children. A later owner
  ## refusal must release all the storage those earlier operations acquired.
  let filler = alloc(1024*1024-getOccupiedMem()-131072)
  assert filler != nil
  var pressure = default(array[1024, nil pointer])
  var used = 0
  while 1024*1024-getOccupiedMem() > headroom:
    assert used < pressure.len
    let remaining = 1024*1024-getOccupiedMem()-headroom
    pressure[used] = alloc(if remaining > 512: 256 else: 16)
    assert pressure[used] != nil
    inc used
  let before = getOccupiedMem()
  assert 1024*1024-before >= 16
  if capture:
    let refused = decodeJamProgram(Tiny, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0))
    assert refused.error == ProgramError.AllocationRefused
  else:
    let refused = newPreparedProgram(tiny, defaultPreparedLimits(Cycles))
    assert refused.error == PreparationError.LimitExceeded
  assert getOccupiedMem() == before
  for i in 0..<used: dealloc(pressure[i])
  dealloc(filler)

checkOwnerRefusal(64, true)
for headroom in [128, 192, 256, 320, 384, 448, 512]:
  checkOwnerRefusal(headroom, false)
assert newPreparedProgram(tiny, defaultPreparedLimits(Cycles)).error == PreparationError.None
echo "PVM code allocation refusal passed"
