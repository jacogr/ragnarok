#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Perturb placement of the original Sieve machine code on a single Linux x86-64 runner."""

import json
import os
from pathlib import Path
import re
import shutil
from statistics import median
import sys

from native_checks import NativeChecks
from pvm_ci_performance import digest
from pvm_sieve_canonical_sampling import BUILD, PRIOR, REVISIONS, SieveImages, prepare_inputs, sample


PAIRS = 11
PLACEMENTS = (('baseline', 0), ('candidate', 0), ('baseline', 48),
              ('candidate', 16), ('baseline', 64), ('candidate', 64))
# These x86-64 ELF relocations encode link addresses and displacements, not opcodes.
LINK_OPERANDS = {
    'R_X86_64_64': 8,
    'R_X86_64_32': 4,
    'R_X86_64_32S': 4,
    'R_X86_64_PC32': 4,
    'R_X86_64_PLT32': 4,
    'R_X86_64_GOTPCREL': 4,
    'R_X86_64_GOTPCRELX': 4,
    'R_X86_64_REX_GOTPCRELX': 4,
    'R_X86_64_TPOFF32': 4,
}


class CaptureLinks(NativeChecks):
    """Record the canonical Clang invocation while passing its arguments through verbatim."""

    def __init__(self):
        super().__init__(BUILD)
        self.clang = shutil.which('clang')
        if self.clang is None:
            raise RuntimeError('Canonical Clang is missing')
        tool_folder = BUILD/'layout-tools'
        tool_folder.mkdir()
        shim = tool_folder/'clang'
        shim.write_text(f'''#!{sys.executable}
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
if '-o' in args:
    output = Path(args[args.index('-o')+1]).name
    if output in ('baseline-guest', 'candidate-guest') and '-c' not in args:
        Path({str(BUILD)!r}, output+'-link.json').write_text(json.dumps(
            dict(command=[{self.clang!r}, *args], directory=os.getcwd()))+'\\n')
os.execv({self.clang!r}, [{self.clang!r}, *args])
''')
        shim.chmod(0o755)
        self.path = str(tool_folder)+os.pathsep+os.environ['PATH']

    def build(self, compiler, source, name, *, environment, **options):
        """Route just the canonical compiler processes through the transparent capture shim."""
        return super().build(compiler, source, name,
                             environment=dict(environment, PATH=self.path), **options)


def text_section(runner, image, label):
    """Read the complete executable text bytes and ELF virtual address."""
    meta = runner.command(['readelf', '-SW', image], label+'-text-address')
    entries = re.findall(r'^\s*\[\s*\d+\]\s+\.text\s+\S+\s+(\w+)\s+(\w+)\s+(\w+)',
                         meta['output'], re.MULTILINE)
    if len(entries) != 1:
        raise RuntimeError('Missing unique .text section for '+label)
    address, first, length = (int(field, 16) for field in entries[0])
    code = image.read_bytes()[first:first+length]
    if len(code) != length:
        raise RuntimeError('Incomplete .text bytes for '+label)
    return address, code


def text_operands(runner, image, label, start):
    """Locate exact relocation fields relative to .text and retain their symbolic targets."""
    receipt = runner.command(['readelf', '-Wr', image], label+'-relocs')
    active = False
    operands = {}
    for line in receipt['output'].splitlines():
        if line.startswith('Relocation section '):
            active = line.startswith("Relocation section '.rela.text'")
        elif active and re.match(r'^[a-f0-9]+\s+[a-f0-9]+\s+R_X86_64_', line):
            offset, _, kind, *symbol = line.split()
            key = int(offset, 16)-start
            if key in operands:
                raise RuntimeError(f'Duplicate .text relocation at {key:#x} in {label}')
            operands[key] = (kind, *symbol[1:])
    if not operands:
        raise RuntimeError('No instruction relocations for '+label)
    return operands


def pad_inputs(runner, lengths):
    """Build only inert linker padding with byte alignment directly before .text."""
    script = BUILD/'sieve-layout.ld'
    script.write_text('SECTIONS { .pvm_layout_pad : { KEEP(*(.pvm_layout_pad)) } } INSERT BEFORE .text;\n')
    pads = {}
    for length in sorted(lengths):
        assembly = BUILD/f'layout-pad-{length}.s'
        assembly.write_text(f'.section .pvm_layout_pad,"ax",@progbits\n.space {length}\n'
                            '.section .note.GNU-stack,"",@progbits\n')
        pads[length] = BUILD/f'layout-pad-{length}.o'
        runner.command(['clang', '-c', assembly, '-o', pads[length]], f'layout-pad-{length}-assemble')
    return script, pads


def relink(runner, record, label, extra):
    """Reuse the exact original compiler products and link arguments with only the placement flags."""
    arguments = record['command'].copy()
    out = BUILD/(label+'-guest')
    arguments[arguments.index('-o')+1] = str(out)
    runner.verify()
    result = runner.checks.command(arguments+['-Wl,--emit-relocs', *extra], label+'-link',
                                   cwd=Path(record['directory']), timeout=180)
    if result['exit_code']:
        raise RuntimeError('Diagnostic relink failed: '+result['log'])
    runner.verify()
    runner.seal([out])
    return out


def verify_code(original, new, expected, relocations, shifted_relocations, label):
    """Permit byte differences only in matching relocation operands from the original link."""
    address, code = original
    moved, revised = new
    if moved-address != expected or len(code) != len(revised):
        raise RuntimeError(f'Unexpected text shift or size for {label}: {moved-address:+d}')
    if relocations != shifted_relocations:
        offset = min(key for key in relocations.keys() | shifted_relocations.keys()
                     if relocations.get(key) != shifted_relocations.get(key))
        raise RuntimeError(f'Changed text relocation in {label} at {offset:#x}: '
                           f'{relocations.get(offset)} vs {shifted_relocations.get(offset)}')
    permitted = bytearray(len(code))
    for offset, target in relocations.items():
        width = LINK_OPERANDS.get(target[0], 0)
        if width and 0 <= offset <= len(code)-width:
            permitted[offset:offset+width] = b'\x01'*width
    changes = 0
    for index, (left, right) in enumerate(zip(code, revised)):
        if left != right:
            if not permitted[index]:
                raise RuntimeError(f'Non-relocation text byte changed in {label} at {index:#x}')
            changes += 1
    return changes


def prepare_images(runner):
    """Reproduce the canonical hashes and qualify each code-placement intervention."""
    runner.checks = CaptureLinks()
    ordinary = runner.images_for_sieve()
    if {role: digest(path) for role, path in ordinary.items()} != PRIOR:
        raise RuntimeError('Canonical benchmark binary hashes changed')
    script, pads = pad_inputs(runner, {shift for _, shift in PLACEMENTS if shift})
    images, receipts = {}, {}
    for role, image in ordinary.items():
        record = json.loads((BUILD/(image.name+'-link.json')).read_text())
        linked = record['command'][record['command'].index('-o')+1]
        if (Path(record['directory'])/linked).resolve() != image:
            raise RuntimeError('Canonical linked output does not match its receipt')
        original = text_section(runner, image, role)
        zero_label = f'{role}-layout-zero'
        zero = relink(runner, record, zero_label, [])
        if original != text_section(runner, zero, zero_label):
            raise RuntimeError('Relocation-retaining control changed canonical instructions: '+role)
        relocations = text_operands(runner, zero, zero_label, original[0])
        for version, shift in PLACEMENTS:
            if version != role:
                continue
            label = f'{role}-layout-{shift}'
            path, addr, changes = image, original[0], 0
            if shift:
                path = relink(runner, record, label, [str(pads[shift]), '-Wl,-T,'+str(script)])
                moved = text_section(runner, path, label)
                addr = moved[0]
                shifts = text_operands(runner, path, label, addr)
                changes = verify_code(original, moved, shift, relocations, shifts, label)
            images[role, shift] = path
            receipts[role, shift] = dict(sha256=digest(path), text_address=addr, shift=shift,
                text_size=len(original[1]), relocated_bytes=changes)
            print(f'Qualified {label} ({changes} relocated .text bytes)', flush=True)
    a, b = (receipts[key]['text_address'] for key in PLACEMENTS[:2])
    if (b-a) % 64 != 48:
        raise RuntimeError('Canonical entry placement changed')
    cpu = Path('/proc/cpuinfo').read_text().splitlines()
    model = next(row.partition(':')[2].strip() for row in cpu if row.startswith('model name'))
    (BUILD/'sieve-layout-images.json').write_text(json.dumps(dict(revisions=REVISIONS, cpu=model,
        images=[dict(role=key[0], **row) for key, row in receipts.items()]), indent=2)+'\n')
    return images


def process_order(pair):
    """Rotate order and reverse every other group so all six images alternate positions."""
    start = pair % len(PLACEMENTS)
    rotated = PLACEMENTS[start:]+PLACEMENTS[:start]
    if pair//len(PLACEMENTS) % 2:
        return rotated[::-1]
    return rotated


def publish(runs, environments):
    """Report matched-placement comparisons in addition to raw canonical controls."""
    rows = ['# Canonical Sieve placement experiment', '',
            '| Size | Control | Compared | Control ms | Compared ms | Paired CPU | Slower pairs |',
            '| ---: | --- | --- | ---: | ---: | ---: | ---: |']
    for size in environments:
        a, b, a48, b16, a64, b64 = PLACEMENTS
        for control, compared in ((a,b), (a,a48), (b,b16), (a,b16), (a48,b), (a,a64), (b,b64)):
            x = [runs[size, pair, *control]['warm_cpu_ns'] for pair in range(PAIRS)]
            y = [runs[size, pair, *compared]['warm_cpu_ns'] for pair in range(PAIRS)]
            delta = median((right/left-1)*100 for left,right in zip(x,y))
            rows.append(f'| {size} | {control[0]} +{control[1]} | {compared[0]} +{compared[1]} | '
                        f'{median(x)/1e6:.5f} | {median(y)/1e6:.5f} | {delta:+.2f}% | '
                        f'{sum(right>left for left,right in zip(x,y))}/{PAIRS} |')
    (BUILD/'summary.md').write_text('\n'.join(rows)+'\n')


def main():
    """Run strictly sequential full-state Sieve measurements for each qualified placement."""
    BUILD.mkdir(parents=True, exist_ok=True)
    runner = SieveImages()
    environments = prepare_inputs(runner)
    images = prepare_images(runner)
    results = {}
    for size, env in environments.items():
        for pair in range(PAIRS):
            for role, shift in process_order(pair):
                results[size, pair, role, shift] = sample(
                    runner, images[role, shift], env, size, f'layout-{shift}', role, pair)
            if len({tuple(results[size, pair, *key]['work']) for key in PLACEMENTS}) != 1:
                raise RuntimeError(f'Warm native work changed at size {size}, pair {pair}')
            print(f'Completed Sieve {size} placement pair {pair+1}/{PAIRS}', flush=True)
            receipt = [dict(size=k[0], pair=k[1], role=k[2], shift=k[3], **v)
                       for k, v in results.items()]
            (BUILD/'sieve-layout-timings.json').write_text(json.dumps(receipt, indent=2)+'\n')
    runner.verify()
    publish(results, environments)


if __name__ == '__main__':
    main()
