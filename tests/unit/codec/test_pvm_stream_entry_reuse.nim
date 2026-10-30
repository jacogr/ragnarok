# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Reordered source entries retain previously admitted headers under exact node and work ceilings.
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step

proc checkEntry(source: Program, memory: Memory, prepared: PreparedProgram, pc: uint64) =
  ## A fresh input shares only the prepared source/cache; literal trap behavior is not another engine's output.
  var registers = default(RegisterFile)
  registers[7] = RegisterValue(100+pc)
  let info = MachineInfo(pc: CodeAddress(pc), gas: MachineGas(1000000), registers: registers)
  let input = captureMachine(source, memory, info)
  if input.error != MachineError.None: echo "ENTRY_REUSE_INPUT_ERROR,", ord(input.error)
  assert input.error == MachineError.None
  let actual = execute(input.value, ExecutionStepLimit(3), prepared)
  if actual.error != StepError.None:
    # Preserve the exact entry/local reason so the unfixed-source negative control cannot pass for an unrelated crash.
    echo "ENTRY_REUSE_LOCAL_ERROR,", pc, ",", ord(actual.error)
  assert actual.error == StepError.None
  if actual.value.exit != StepExit.Panic: echo "ENTRY_REUSE_EXIT_ERROR,", ord(actual.value.exit)
  assert actual.value.exit == StepExit.Panic
  let posterior = machineInfo(actual.value.machine).value
  if uint64(posterior.pc) != 0 or uint64(posterior.gasDeficit) != 0:
    echo "ENTRY_REUSE_CPU_ERROR,", uint64(posterior.pc), ",", uint64(posterior.gasDeficit)
  assert uint64(posterior.pc) == 0 # Halt/panic have the public normalized terminal PC.
  assert uint64(posterior.gasDeficit) == 0
  for index in 0..<13:
    # Neither unlikely nor trap mutates any register, including the distinct invocation marker.
    if posterior.registers[index] != registers[index]: echo "ENTRY_REUSE_REGISTER_ERROR,", pc, ",", index
    assert posterior.registers[index] == registers[index]
  let retained = machineInfo(input.value).value
  if retained.pc != info.pc or retained.gas != info.gas: echo "ENTRY_REUSE_IMMUTABLE_ERROR,", pc
  assert retained.pc == info.pc and retained.gas == info.gas

proc checkOrder(order: openArray[uint64], nodes, work: uint64) =
  ## Exact ceilings admit each requested two-node suffix once, regardless of later overlapping emission.
  let bytes = @[0'u8, 0, 3, 2, 2, 0, 7] # Zero jumps; unlikely, unlikely, trap; all three boundaries.
                                        # Decode admission counts the full framed blob; execution's code-only limit below stays exactly three.
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(uint64(bytes.len)),
      JumpCountLimit(0))
  if decoded.error != ProgramError.None: echo "ENTRY_REUSE_DECODE_ERROR,", ord(decoded.error)
  assert decoded.error == ProgramError.None
  let source = decoded.value
  let memory = captureMemory([], PageLimit(0)).value
  var limits = defaultPreparedLimits(GasCycleLimit(1000000))
  limits.resources.codeBytes = ProgramByteLimit(3)
  limits.resources.nodes = ExecutionNodeLimit(nodes)
  limits.resources.preparation = ExecutionPreparationLimit(work)
  let admitted = newPreparedProgram(source, limits)
  if admitted.error != PreparationError.None: echo "ENTRY_REUSE_ADMISSION_ERROR,", ord(admitted.error)
  assert admitted.error == PreparationError.None
  let prepared = admitted.value
  for pc in order:
    # Each initial entry gets its own complete header, while operation nodes may overlap in source space.
    checkEntry(source, memory, prepared, pc)
  let full = preparedInfo(prepared)
  if full.error != PreparationError.None: echo "ENTRY_REUSE_USAGE_ERROR,", ord(full.error)
  assert full.error == PreparationError.None
  if full.value.streamNodes != nodes or full.value.preparationUnits != work:
    echo "ENTRY_REUSE_CAPACITY_ERROR,", full.value.streamNodes, ",", full.value.preparationUnits,
        ",", nodes, ",", work
  assert full.value.streamNodes == nodes and full.value.preparationUnits == work
  for repeat in 0..<3:
    for pc in order:
      # A full cache must service every already-admitted entry without allocating or reserving more work.
      checkEntry(source, memory, prepared, pc)
      let current = preparedInfo(prepared)
      if current.error != PreparationError.None: echo "ENTRY_REUSE_CACHED_USAGE_ERROR,", ord(current.error)
      assert current.error == PreparationError.None
      if current.value.streamNodes != nodes or current.value.preparationUnits != work:
        echo "ENTRY_REUSE_CACHED_CAPACITY_ERROR,", pc, ",", current.value.streamNodes, ",",
            current.value.preparationUnits
      assert current.value.streamNodes == nodes and current.value.preparationUnits == work

checkOrder([1'u64, 0], 4, 11)
for order in [[0'u64, 1, 2], [0'u64, 2, 1], [1'u64, 0, 2],
    [1'u64, 2, 0], [2'u64, 0, 1], [2'u64, 1, 0]]:
  # All permutations use the exact six-node/fifteen-work capacity, followed by repeated reordered reuse.
  checkOrder(order, 6, 15)
echo "PASS reordered entry headers / exact node-work ceilings / fresh inputs / repeated full-cache reuse"
