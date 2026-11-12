#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Transcribe pinned simulator.rs SLOT_MASKS, REGISTER_MASKS and RETIRE_MASK_TABLE.

These immutable tables retain upstream vector widths and indexing; scheduling stays Nimony.
"""
from formatting import nim
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def row(values, suffix):
    """Type each constant explicitly so nested array inference preserves lane width."""
    return '[' + ', '.join(str(value) + suffix for value in values) + ']'


def render():
    """Expand the source constant loops without replacing table lookups by arithmetic."""
    source = ROOT / 'vendor/polkavm/crates/polkavm-common/src/simulator.rs'
    lines = ['# Copyright (c) 2026 Ragnarök contributors',
             '# SPDX-License-Identifier: MIT OR Apache-2.0', '',
             '## Generated simulator mask tables; see generate_simulator_tables.py and LICENSES/NOTICE.md.',
             '## Source SHA256: ' + hashlib.sha256(source.read_bytes()).hexdigest(), '',
             'const slotMasks = [']
    for slot in range(32):
        lines.append('  ' + row((-1 if lane == slot else 0 for lane in range(32)), "'i8") + ',')
    lines += [']', '', 'const registerMasks = [']
    for register in range(16):
        lines.append('  ' + row((1 << register for _ in range(32)), "'u16") + ',')
    lines += [']', '', 'const retireMasks = [']
    for head in range(32):
        lines.append('  [')
        for count in range(33):
            lines.append('    ' + row((-1 if (lane-head) % 32 < count else 0 for lane in range(32)), "'i8") + ',')
        lines.append('  ],')
    lines += [']', '']
    return '\n'.join(lines)


def main():
    """Write the derived constants or refuse stale checked-in output."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = Path(__file__).with_name('simulator_tables.nim')
    expected = nim(render())
    if args.check:
        # No output change is permitted during validation.
        assert target.read_text() == expected, 'faithful simulator tables differ'
    else:
        # Generation only touches this experiment's derived constants.
        target.write_text(expected)


if __name__ == '__main__':
    main()
