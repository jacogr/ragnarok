# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative runtime fixture for memory-step fault-page and local-result selection contracts.
## Chooses a non-fault outcome or local simulation refusal and attempts its forbidden accessor.

import std/cmdline
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/gas
import ../../src/pvm/step

let selection = paramStr(1)
var outcome = default(StepOutcome)
if selection != "default":
  # A compact load-i16 plus trap produces success, protected panic or gas refusal.
  var code = @[55'u8, 0, 0, 0, 1, 0, 0]
  var mask = 65'u8
  var registers = default(RegisterFile)
  if selection == "panic":
    # Absolute zero remains protected regardless of supplied memory access.
    code[4] = 0
  elif selection == "fault":
    # The approved PolkaVM overflow read supplies a genuine fault-page positive control.
    code = @[55'u8, 0, 255, 255, 255, 255, 0]
  elif selection == "halt":
    # The dynamic sentinel yields a real Halt outcome with no fault metadata.
    code = @[50'u8, 0, 0]
    mask = 5
    registers[0] = RegisterValue(0xffff0000'u64)
  var bytes = @[0'u8, 0, byte(code.len)]
  # Construct a short program without invoking an upstream assembler or copied binary fixture.
  for value in code: bytes.add(value)
  bytes.add(mask)
  let program = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0)).value
  let memory = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))], PageLimit(1)).value
  let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(
      if selection == "cycle_limit": 1000 else: 0),
    blockCharged: selection notin ["oog", "cycle_limit"], registers: registers)).value
  let evaluated = stepMemory(source, GasCycleLimit(if selection == "cycle_limit": 0 else: 100))
  # The local simulation refusal fails at value selection; non-fault exits fail at fault-page selection, while fault succeeds.
  outcome = evaluated.value
else:
  # A default outcome has no fault reason and cannot provide an invented zero page.
  discard
discard outcome.faultPage
