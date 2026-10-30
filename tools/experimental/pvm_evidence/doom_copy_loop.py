#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Retain the manually inspected page-loop bounds and validate all eight inert ELF disassemblies."""
import hashlib
import json
from pathlib import Path
import re

BASE = Path(__file__).resolve().parents[2]/'build/pvm-doom-e2e-evidence/41028220399'
rows = []
for path in sorted(BASE.glob('*-statebytes.asm')):
    # Author inspected production loop instruction flow; require the same precise shape for all variants.
    text = path.read_text()
    start = int(re.search(r'\n([0-9a-f]+) <stateBytes_0_dooysw6bn>:', text)[1], 16)
    arm = path.name.startswith('arm64-')
    head = start+(0x3ac if arm else 0x470)
    backedge = start+(0x420 if arm else 0x509)
    instructions = []
    for line in text.splitlines():
        # Read only objdump's bounded instruction records; no native artifact is imported or executed.
        match = re.match(r'\s*([0-9a-f]+):\s+.*?\t(.*)', line)
        if match:
            instructions.append((int(match[1], 16), match[2]))
    loop = [(at, op) for at, op in instructions if head <= at <= backedge]
    assert loop[0][0] == head and loop[-1][0] == backedge
    assert f'0x{head:x}' in loop[-1][1]
    assert loop[-1][1].startswith('b.ne' if arm else 'jne')
    allocations = [at for at, op in instructions if '<rawAlloc_' in op]
    assert len(allocations) == 1 and allocations[0] < head
    assert not any('<rawAlloc_' in op or '<rawDealloc_' in op for at, op in loop)
    copies = [at for at, op in loop if '<memcpy@plt>' in op]
    assert len(copies) == 1
    before_copy = [op for at, op in loop if at < copies[0]][-3:]
    assert any(('#0x1008' in op and 'w2,' in op) if arm else
        ('$0x1008' in op and '%edx' in op) for op in before_copy)
    calls = [op for at, op in loop if op.startswith('bl\t' if arm else 'callq\t')]
    assert calls and all('<memcpy@plt>' in op or '<add_1_sysvq0asl>' in op for op in calls)
    rows.append(dict(listing=path.name, listing_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        function_start=hex(start), page_loop_head=hex(head), page_loop_backedge=hex(backedge),
        whole_sequence_allocation=hex(allocations[0]), whole_sequence_allocation_outside_page_loop=True,
        only_page_loop_memcpy=hex(copies[0]), page_loop_memcpy_bytes=4104,
        interpretation='Each iteration copies one PageImage then serializes its index/access/4096bytes; full-sequence extraction occurs before the loop. Output-string growth via add is expected, not a page-array copy.'))
assert len(rows) == 8
receipt = dict(status='author-actual-copy-loop-inspection-PASS-awaiting-independent-gate',
    revision='fdd863842221f43497e21345d021d846d14042a5', run=41028220399,
    normal_and_trace_production_and_eager_both_cpus=rows, native_artifact_execution=False,
    performance_claim=False, full_cohort_cleared=False)
(BASE/'author-copy-loop-inspection.json').write_text(json.dumps(receipt, indent=2)+'\n')
print('PASS: eight actual normal/trace endpoint disassemblies; one4104-byte page copy, no full-array allocation inside page loop')
