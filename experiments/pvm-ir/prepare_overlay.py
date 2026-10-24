# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Generate an experiment-only step module by replacing its instruction cache, not its semantics."""
import difflib
from pathlib import Path


def generate(root: Path, build: Path):
    """Require exact edit anchors and save the complete generated diff for review."""
    source = root / 'src/pvm/step.nim'
    original = source.read_text()
    start = original.index('  InstructionCache = object')
    end = original.index('  HostCallId*', start)
    generated = original[:start] + '  InstructionCache = seq[ProgramResult[Instruction]] ## Experiment-only dense immutable byte-PC table.\n' + original[end:]
    old_import = 'import ./[program, machine, registers, gas, gas_plan, gas_memo]'
    assert generated.count(old_import) == 1
    generated = generated.replace(old_import, 'import std/assertions\nimport ../../src/pvm/[program, machine, registers, gas, gas_plan, gas_memo]')
    generated = generated.replace('Fixed-size scalar-only decoder memo belongs to one program invocation, including its host resumptions.', 'Experiment-only dense decoded table, immutable after preparation.')
    start = generated.index('proc cachedInstruction(')
    end = generated.index('# Evaluate recursive Psi iteratively', start)
    generated = generated[:start] + '''proc cachedInstruction(program: Program, address: CodeAddress,
    cache: InstructionCache): ProgramResult[Instruction] {.inline.} =
  ## Prepared operands are indexed by guest byte PC; invalid PCs use the original failure path.
  if uint64(address) < uint64(cache.len):
    let slot = int(uint64(address))
    if cache[slot].error == ProgramError.None: return cache[slot]
  instruction(program, address)

''' + generated[end:]
    # The shared production templates only read the immutable prepared cache.
    assert generated.count('instructions: var InstructionCache') == 9
    generated = generated.replace('instructions: var InstructionCache', 'instructions: InstructionCache')
    generated += '''

type PreparedExecution* = object ## Immutable decoded table bound to its exact source snapshot.
  source: Machine
  instructions: InstructionCache

proc prepareExecution*(source: Machine): PreparedExecution =
  ## Prepare operands only; gas simulations and their local limits remain in executeBudget.
  result = PreparedExecution(source: source, instructions: @[])
  let owner = programOf(source)
  if owner.error != MachineError.None: return
  let size = codeLength(owner.value)
  assert size.error == ProgramError.None and size.value <= 65536
  result.instructions = newSeq[ProgramResult[Instruction]](int(size.value))
  var pc = 0'u64
  while pc < size.value:
    # Validated program layout advances by exactly its original bitmap-defined instruction extent.
    let decoded = instruction(owner.value, CodeAddress(pc))
    assert decoded.error == ProgramError.None
    result.instructions[int(pc)] = decoded
    pc += 1 + uint64(decoded.value.skip)

proc executePrepared*(plan: PreparedExecution, stepLimit: ExecutionStepLimit,
    gasLimit: GasCycleLimit): StepResult =
  ## Reuse the unchanged production execution body, price memo and publication boundary.
  var remaining = uint64(stepLimit)
  var prices = initBlockChargeCache()
  var unusedCursor = default(ExecutionCursor) # Keep current master's ordinary source-validation path.
  executeBudget[false](plan.source, remaining, gasLimit, prices, plan.instructions, unusedCursor, false)

proc preparedBytes*(plan: PreparedExecution): int =
  ## Dense PC lookup is intentionally simple; operand bytes consume empty slots in this probe.
  plan.instructions.len * sizeof(ProgramResult[Instruction])
'''
    path = build / 'prepared_step.nim'
    path.write_text(generated)
    (build / 'prepared-step.diff').write_text(''.join(difflib.unified_diff(
        original.splitlines(keepends=True), generated.splitlines(keepends=True),
        fromfile='src/pvm/step.nim', tofile='build/pvm-ir-experiment/prepared_step.nim')))
    return path
