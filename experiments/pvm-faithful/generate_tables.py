#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Transcribe JamV1 opcode numbers/formats from the pristine pin, with no semantic rewriting.

The generated table is committed alongside the port; --check verifies that source mapping.
Instruction execution, decoding and gas accounting remain explicit Nimony source.
"""
from formatting import nim
import argparse
import hashlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'vendor/polkavm/crates/polkavm-common/src/program.rs'
FORMATS = ('None', 'RegImm', 'RegImmOffset', 'RegImm2', 'Regs2Imm', 'Regs2Offset',
           'Regs3', 'Offset', 'Imm', 'Imm2', 'Regs2', 'Regs2Imm2', 'RegImm64')


def render():
    """Require the pinned macro grammar and emit one exhaustive numeric mapping."""
    source = SOURCE.read_text()
    section = source.split('    ISA_JamV1,\n', 1)[1].split('\n}', 1)[0]
    groups = re.findall(r'\[([^\]]*)\]', section)
    assert len(groups) == len(FORMATS)
    rows = []
    for form, group in zip(FORMATS, groups):
        entries = re.findall(r'^\s*(\w+)\s*=\s*(\d+),\s*$', group, re.M)
        assert entries
        rows.extend((int(number), name, form) for name, number in entries)
    assert len({number for number, _, _ in rows}) == len(rows)
    output = ['# Copyright (c) 2026 Ragnarök contributors',
              '# SPDX-License-Identifier: MIT OR Apache-2.0', '',
              '## Generated JamV1 table derived from PolkaVM program.rs; see LICENSES/NOTICE.md.',
              '## Regenerate with generate_tables.py; numeric gaps are invalid instructions.',
              '## Source SHA256: '+hashlib.sha256(SOURCE.read_bytes()).hexdigest(), '',
              'import std/assertions', '', 'type', '  Opcode* {.pure.} = enum',
              '    ## The source JamV1 opcode numbers, with an explicit invalid sentinel.']
    output.extend('    op_'+name+' = '+str(number) for number, name, _ in sorted(rows))
    output += ['    op_invalid = 256', '  OperandFormat* {.pure.} = enum',
               '    ## Source macro operand group; these choose the pinned read_args routines.',
               '    '+', '.join('fmt'+form for form in ('Invalid', *FORMATS)), '',
               'proc operandFormat*(raw: byte): OperandFormat =',
               '  ## Reject gaps instead of assuming contiguous enum membership.', '  case raw']
    for form in FORMATS:
        output += ['  of '+', '.join(str(number) for number, _, kind in sorted(rows) if kind == form)+':',
                   '    result = OperandFormat.fmt'+form]
    output += ['  else: result = OperandFormat.fmtInvalid', '',
               'const opcodeTable = [']
    names = {number: name for number, name, _ in rows}
    for first in range(0, 256, 8):
        output.append('  '+', '.join('Opcode.op_'+names.get(i, 'invalid')
                      for i in range(first, first+8))+(',' if first < 248 else ''))
    output += [']', '', 'proc opcode*(raw: byte): Opcode =',
               '  ## Lookup validates gaps without an unchecked enum cast.',
               '  opcodeTable[int(raw)]', '']
    return '\n'.join(output)


def main():
    """Write only the generated table, or compare without modifying it."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = Path(__file__).with_name('opcodes.nim')
    expected = nim(render())
    if args.check:
        assert target.read_text() == expected, 'faithful opcode transcription differs from pin'
    else:
        target.write_text(expected)


if __name__ == '__main__':
    main()
