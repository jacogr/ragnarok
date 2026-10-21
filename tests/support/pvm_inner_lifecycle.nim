# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original literal inner blobs and bounded lifecycle fixtures shared by unit and strict misuse probes.

import ../../src/pvm/[inner_machines, machine, program, step, gas]

proc innerLimits*(): InnerMachineLimits =
  ## Independent local budgets permit the protocol's whole 63-slot map with tiny original programs.
  InnerMachineLimits(items: InnerMachineLimit(63), program: ProgramByteLimit(8192),
    total: InnerProgramLimit(65536), jumps: JumpCountLimit(32), pages: PageLimit(4),
        steps: ExecutionStepLimit(100), cycles: GasCycleLimit(1000))
proc innerBlob*(): seq[byte] =
  ## Empty jump table, two code bytes (jump_ind r0) and a single marked opcode, all authored literally.
  @[0'u8, 0, 2, 50, 0, 1]
proc innerMemory*(blob = innerBlob()): Memory =
  ## Copy supplied bytes into independent read-only pages; later caller mutation cannot change the owner.
  var pages: seq[PageImage] = @[]
  for index in 0..<((blob.len+4095) div 4096):
    var page = PageImage(index: PageIndex(uint32(16+index)), access: PageAccess.ReadOnly)
    for offset in 0..<min(4096, blob.len-index*4096):
      page.bytes[offset] = blob[index*4096+offset] # Every unused byte remains explicit zero storage.
    pages.add(page)
  captureMemory(pages, PageLimit(3)).value
proc innerRegisters*(size = 6'u64, pointer = 65536'u64, entry = 0'u64): RegisterFile =
  ## Sentinel registers catch unwanted mutations outside r7; all fields are initialized explicitly.
  result = default(RegisterFile)
  for index in 0..<13: result[index] = RegisterValue(uint64(index+100))
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(size)
  result[9] = RegisterValue(entry)

proc preparedInnerMachine*(machines: InnerMachines, gas: MachineGas, registers: RegisterFile,
    memory: Memory): InnerMachineResult[InnerMachineTransition] =
  ## Test preparation compiles the source first, then exercises current instance creation at the caller's gas.
  var source = registers
  source[7] = RegisterValue(0)
  source[8] = registers[7]
  source[9] = registers[8]
  let compiled = compileInnerModule(machines, MachineGas(high(uint64)), source, memory)
  if compiled.error != InnerMachineError.None:
    compiled # A source capture refusal carries only its original typed reason.
  else:
    let prepared = compiled.value
    if prepared.response.action != HostAction.Continue or uint64(prepared.response.registers[7]) >= 128:
      compiled # A protocol HUH/FULL response cannot authorize instantiation.
    else:
      var instance = registers
      instance[7] = prepared.response.registers[7]
      instance[8] = registers[9]
      createInnerMachine(prepared.machines, gas, instance,
          memory) # Capture the distinct current instance transition.
