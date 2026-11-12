#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Generate only serialization arms for the upstream public decoded instruction enum.

No candidate decoding logic supplies expectations. The macro operand signatures determine
which fields the reference exports; all raw bits, including unnormalized registers, survive.
"""
import argparse
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from formatting import rust

ROOT = Path(__file__).resolve().parents[3]


def render():
    """Emit exhaustive JamV1 enum serialization with an explicit invalid representation."""
    source = (ROOT / 'vendor/polkavm/crates/polkavm-common/src/program.rs').read_text()
    groups = re.findall(r'\[([^\]]*)\]', source.split('    ISA_JamV1,\n', 1)[1].split('\n}', 1)[0])
    signatures = ('', 'ax', 'axy', 'axy', 'abx', 'abx', 'abc', 'x', 'x', 'xy', 'ab', 'abxy', 'aw')
    output = ['// Copyright (c) 2026 Ragnarök contributors',
              '// SPDX-License-Identifier: MIT OR Apache-2.0', '',
              '//! Generated serialization of pinned PolkaVM public enum fields.',
              'use polkavm_common::program::Instruction;', '',
              'pub fn fields(instruction: Instruction) -> (u32, [u64; 6]) {',
              '    // Keep raw register bits and immediate two-complement encodings.',
              '    match instruction {', '        Instruction::invalid => (256, [0; 6]),']
    for signature, group in zip(signatures, groups):
        for name, number in re.findall(r'^\s*(\w+)\s*=\s*(\d+),\s*$', group, re.M):
            pattern = name + ('('+', '.join(signature)+')' if signature else '')
            values = []
            for key in 'abcxyw':
                if key not in signature: values.append('0')
                elif key in 'abc': values.append(key+'.raw_unparsed() as u64')
                elif key == 'w': values.append('w')
                else: values.append(key+' as u32 as u64')
            output.append('        Instruction::'+pattern+' => ('+number+', ['+', '.join(values)+']),')
    output += ['        other => panic!("foreign ISA instruction: {other:?}"),', '    }', '}', '']
    return '\n'.join(output)


def main():
    """Verify or regenerate the source-defined serializer; it contains no opcode semantics."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = Path(__file__).with_name('src') / 'decode_match.rs'
    value = rust(render())
    if args.check:
        assert target.read_text() == value
    else:
        target.write_text(value)


if __name__ == '__main__':
    main()
