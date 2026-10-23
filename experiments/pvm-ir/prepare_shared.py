# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Generate a bounded program-owned preparation experiment without editing production files."""
import difflib
from pathlib import Path


def generate_shared(root: Path, build: Path):
    """Keep semantic bodies intact, replace cache storage/lookup, and add program-bound entry points."""
    original = (root / 'src/pvm/step.nim').read_text()
    lines = original.splitlines(keepends=True)
    matches = [i for i, line in enumerate(lines) if 'InstructionCache = array[16,' in line]
    assert len(matches) == 1
    lines[matches[0]] = '''  CacheData = ref object ## Private immutable decoded records and bounded byte-PC index.
    owner: Program
    entries: seq[ProgramResult[Instruction]]
    lookup: seq[uint16]
  InstructionCache = nil CacheData ## Default execution paths retain the original decoder fallback.
'''
    generated = ''.join(lines)
    old_import = 'import ./[program, machine, registers, gas]'
    assert generated.count(old_import) == 1
    generated = generated.replace(old_import, 'import std/assertions\nimport ../../src/pvm/[program, machine, registers, gas]')
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
    assert generated.count('instructions: var InstructionCache') == 2
    generated = generated.replace('instructions: var InstructionCache', 'instructions: InstructionCache')
    generated += '\n' + (root / 'experiments/pvm-ir/shared_api.nim.inc').read_text()
    # Copy the response-only host scheduler verbatim, substituting only source/cache binding.
    anchor = 'proc executeWithHost*[Context](source: Machine, context: var Context,'
    assert original.count(anchor) == 1
    host = original[original.index(anchor):]
    host = host.replace(anchor, '''proc executeSharedWithHost*[Context](plan: PreparedProgram, memory: Memory,
    info: MachineInfo, context: var Context,''', 1)
    anchor = '  var remaining = uint64(stepLimit)'
    assert host.count(anchor) == 1
    host = host.replace(anchor, '''  let retained = plan.cache
  if retained == nil: return StepResult(status: StepError.InvalidMachine)
  let table: CacheData = retained
  let captured = captureTerminalMachine(table.owner, memory, info)
  if captured.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  let source = captured.value
''' + anchor, 1)
    anchor = 'var instructions = default(InstructionCache)'
    assert host.count(anchor) == 1
    host = host.replace(anchor, 'let instructions = plan.cache', 1)
    generated += '\n' + host
    path = build / 'shared_step.nim'
    path.write_text(generated)
    (build / 'shared-step.diff').write_text(''.join(difflib.unified_diff(
        original.splitlines(keepends=True), generated.splitlines(keepends=True),
        fromfile='src/pvm/step.nim', tofile='build/pvm-ir-experiment/shared_step.nim')))
    return path
