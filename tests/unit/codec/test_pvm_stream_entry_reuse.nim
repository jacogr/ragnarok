# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Reordered source entries retain previously admitted headers under exact node and work ceilings.
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step]

proc checkEntry(source: Program, memory: Memory, prepared: PreparedProgram, pc: uint64) =
  ## A fresh input shares only the prepared source/cache; literal trap behavior is not another engine's output.
  var registers = default(RegisterFile)
  registers[7] = RegisterValue(100+pc)
  let info = MachineInfo(pc: CodeAddress(pc), gas: MachineGas(1000000), registers: registers)
  let input = captureMachine(source, memory, info)
  assert input.error == MachineError.None
  let actual = execute(input.value, ExecutionStepLimit(3), prepared)
  if actual.error != StepError.None:
    # Preserve the exact entry/local reason so the unfixed-source negative control cannot pass for an unrelated crash.
    echo "ENTRY_REUSE_LOCAL_ERROR,", pc, ",", ord(actual.error)
  assert actual.error == StepError.None
  assert actual.value.exit == StepExit.Panic
  let posterior = machineInfo(actual.value.machine).value
  assert uint64(posterior.pc) == 0 # Halt/panic have the public normalized terminal PC.
  assert uint64(posterior.gasDeficit) == 0
  for index in 0..<13:
    # Neither unlikely nor trap mutates any register, including the distinct invocation marker.
    assert posterior.registers[index] == registers[index]
  let retained = machineInfo(input.value).value
  assert retained.pc == info.pc and retained.gas == info.gas

proc checkOrder(order: openArray[uint64], nodes, work: uint64) =
  ## Exact ceilings admit each requested two-node suffix once, regardless of later overlapping emission.
  let decoded = decodeProgram(@[0'u8, 0, 3, 2, 2, 0, 7], CodeAddress(0),
    ProgramByteLimit(3), JumpCountLimit(0)) # Zero jumps; unlikely, unlikely, trap; all three boundaries.
  assert decoded.error == ProgramError.None
  let source = decoded.value
  let memory = captureMemory([], PageLimit(0)).value
  var limits = defaultPreparedLimits(GasCycleLimit(1000000))
  limits.resources.nodes = ExecutionNodeLimit(nodes)
  limits.resources.preparation = ExecutionPreparationLimit(work)
  let admitted = newPreparedProgram(source, limits)
  assert admitted.error == PreparationError.None
  let prepared = admitted.value
  for pc in order:
    # Each initial entry gets its own complete header, while operation nodes may overlap in source space.
    checkEntry(source, memory, prepared, pc)
  let full = preparedInfo(prepared)
  assert full.error == PreparationError.None
  assert full.value.streamNodes == nodes and full.value.preparationUnits == work
  for repeat in 0..<3:
    for pc in order:
      # A full cache must service every already-admitted entry without allocating or reserving more work.
      checkEntry(source, memory, prepared, pc)
      let current = preparedInfo(prepared)
      assert current.error == PreparationError.None
      assert current.value.streamNodes == nodes and current.value.preparationUnits == work

checkOrder([1'u64, 0], 4, 11)
for order in [[0'u64, 1, 2], [0'u64, 2, 1], [1'u64, 0, 2],
    [1'u64, 2, 0], [2'u64, 0, 1], [2'u64, 1, 0]]:
  # All permutations use the exact six-node/fifteen-work capacity, followed by repeated reordered reuse.
  checkOrder(order, 6, 15)
echo "PASS reordered entry headers / exact node-work ceilings / fresh inputs / repeated full-cache reuse"
