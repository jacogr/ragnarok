#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Generate the complete prepared interface around unchanged production semantic bodies."""
import difflib
from prepare_shared import generate_shared


def generate_full(root, build, owned_lookup=False):
    """Bind both pricing policies and callback forms without specializing guest instructions."""
    source = generate_shared(root, build).read_text()
    for old, new in {
        "min(4096'u64, uint64(byteLimit))": "min(1048576'u64, uint64(byteLimit))",
        "min(256'u64, uint64(instructionLimit))": "min(65535'u64, uint64(instructionLimit))",
        'capped at 4096 code bytes': 'capped at 1048576 code bytes',
        'capped at 256 decoded operations': 'capped at 65535 decoded operations',
        'At most 256 records': 'At most 65535 records',
    }.items():
        # Exact anchors make upstream drift a build refusal, rather than a semantic guess.
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    if not owned_lookup:
        # A non-null borrowed parameter avoids an ARC-owning narrowing alias on every guest instruction.
        start = source.index('proc cachedInstruction(')
        end = source.index('# Evaluate recursive Psi iteratively', start)
        source = source[:start] + """proc preparedInstruction(table: CacheData, address: CodeAddress): ProgramResult[Instruction] {.inline.} =
  ## The invocation retains the owner; this checked lookup borrows it without changing its reference count.
  if uint64(address) < uint64(table.lookup.len):
    let index = table.lookup[int(uint64(address))]
    if index != 0: return table.entries[int(index) - 1]
  instruction(table.owner, address)

proc cachedInstruction(program: Program, address: CodeAddress,
    cache: InstructionCache): ProgramResult[Instruction] {.inline.} =
  ## Narrow through a borrowed parameter; absent tables preserve the ordinary decoder fallback.
  if cache != nil: return preparedInstruction(cache, address)
  instruction(program, address)

""" + source[end:]
    original = (root / 'src/pvm/step.nim').read_text()
    start = original.index('template runFallibleHostBody[')
    end = original.index('proc runFallibleHost[', start)
    host = original[start:end].replace('template runFallibleHostBody[', 'template preparedFallibleBody[', 1)
    anchor = 'plan: GasPlan, memo: GasMemo): HostExecutionResult[Reason] ='
    assert host.count(anchor) == 1
    host = host.replace(anchor, 'plan: GasPlan, memo: GasMemo, preparedCache: InstructionCache): HostExecutionResult[Reason] =')
    assert host.count('var instructions = default(InstructionCache)') == 1
    host = host.replace('var instructions = default(InstructionCache)', 'let instructions = preparedCache')
    source += '\n' + host
    start = original.index('proc stepDecoded[')
    end = original.index('# Single-step calls', start)
    single = original[start:end].replace('proc stepDecoded[UsePlan: static[bool]]', 'proc preparedMemoStep', 1)
    single = single.replace('plan: GasPlan = default(GasPlan)', 'memo: GasMemo')
    single = single.replace('evaluateInstruction[UsePlan]', 'memoEvaluateInstruction')
    single = single.replace('cache, decoded, plan)', 'cache, decoded, memo)')
    source += '\n' + single + '\n' + (root / 'experiments/pvm-ir/full_api.nim.inc').read_text()
    source += '\n' + (root / 'experiments/pvm-ir/full_test_adapter.nim.inc').read_text()
    path = build / 'full_step.nim'
    path.write_text(source)
    (build / 'full-step.diff').write_text(''.join(difflib.unified_diff(
        original.splitlines(keepends=True), source.splitlines(keepends=True),
        fromfile='src/pvm/step.nim', tofile='build/pvm-ir-experiment/full_step.nim')))
    return path
