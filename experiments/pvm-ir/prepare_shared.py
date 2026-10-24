# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Generate a bounded program-owned preparation experiment without editing production files."""
import difflib
from pathlib import Path


def generate_shared(root: Path, build: Path):
    """Keep semantic bodies intact, replace cache storage/lookup, and add program-bound entry points."""
    original = (root / 'src/pvm/step.nim').read_text()
    start = original.index('  InstructionCache = object')
    end = original.index('  HostCallId*', start)
    # Replace the complete current cache object, retaining every adjacent semantic type.
    generated = original[:start] + """  CacheData = ref object ## Private immutable decoded records and bounded byte-PC index.
    owner: Program
    entries: seq[ProgramResult[Instruction]]
    lookup: seq[uint16]
  InstructionCache = nil CacheData ## Default execution paths retain the original decoder fallback.
""" + original[end:]
    old_import = 'import ./[program, machine, registers, gas, gas_plan, gas_memo]'
    assert generated.count(old_import) == 1
    generated = generated.replace(old_import, 'import std/assertions\nimport ../../src/pvm/[program, machine, registers, gas, gas_plan, gas_memo]')
    assert generated.count('proc cachedInstruction(') == 1
    start = generated.index('proc cachedInstruction(')
    end = generated.index('# Evaluate recursive Psi iteratively', start)
    generated = generated[:start] + '''proc cachedInstruction(program: Program, address: CodeAddress,
    cache: InstructionCache): ProgramResult[Instruction] {.inline.} =
  ## Zero index entries denote operand bytes; valid PCs select immutable records in constant time.
  if cache != nil:
    let table: CacheData = cache
    if uint64(address) < uint64(table.lookup.len):
      let index = table.lookup[int(uint64(address))]
      if index != 0: return table.entries[int(index) - 1]
  instruction(program, address)

''' + generated[end:]
    # Neither the execution scheduler nor its decoder may mutate a prepared program table.
    assert generated.count('instructions: var InstructionCache') == 9
    generated = generated.replace('instructions: var InstructionCache', 'instructions: InstructionCache')
    generated += '\n' + (root / 'experiments/pvm-ir/shared_api.nim.inc').read_text()
    # Reuse the exact current response-only transition template, changing only cache binding.
    start = original.index('template runHostBody[')
    end = original.index('proc runHost[', start)
    host = original[start:end]
    host = host.replace('template runHostBody[', 'template runSharedHostBody[', 1)
    anchor = 'plan: GasPlan, memo: GasMemo): StepResult ='
    assert host.count(anchor) == 1
    host = host.replace(anchor, 'plan: GasPlan, memo: GasMemo, preparedCache: InstructionCache): StepResult =')
    anchor = 'var instructions = default(InstructionCache)'
    assert host.count(anchor) == 1
    host = host.replace(anchor, 'let instructions = preparedCache')
    generated += '\n' + host + """
proc executeSharedWithHost*[Context](plan: PreparedProgram, memory: Memory,
    info: MachineInfo, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit): StepResult =
  ## Bind the prepared program and pass its immutable operands through the unchanged host template.
  let retained = plan.cache
  if retained == nil: return StepResult(status: StepError.InvalidMachine)
  let table: CacheData = retained
  let captured = captureTerminalMachine(table.owner, memory, info)
  if captured.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  runSharedHostBody[Context, false, false](captured.value, context, handler, stepLimit,
    hostLimit, gasLimit, default(GasPlan), default(GasMemo), retained)
"""
    path = build / 'shared_step.nim'
    path.write_text(generated)
    (build / 'shared-step.diff').write_text(''.join(difflib.unified_diff(
        original.splitlines(keepends=True), generated.splitlines(keepends=True),
        fromfile='src/pvm/step.nim', tofile='build/pvm-ir-experiment/shared_step.nim')))
    return path
