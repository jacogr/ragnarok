# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate independent allocator checkpoints alongside the unchanged native correctness witnesses."""
import re
from storage_growth_report import parse_growth, METRICS


def allocation_phases(engine):
    """Unavailable reopen/reclamation operations never acquire invented allocation observations."""
    phases = ['fixture', 'seed', 'owner', 'publication', 'snapshots', 'extraction', 'reads']
    if engine != 'memory':
        phases.append('reopen')
    if engine != 'journal':
        phases += ['retention', 'maintenance']
    return phases+['closed']


def parse_allocations(output, engine, count, steps, pattern='sweep'):
    """Reparse the complete native trajectory before accepting strictly ordered live-heap counters."""
    phases = allocation_phases(engine)
    rows = []; ordinary = []; finished = False
    for line in output.splitlines():
        # Checkpoints precede the final native duration witnesses and cannot be interleaved afterward.
        if line.startswith('allocation\t'):
            fields = line.split('\t')
            if (finished or len(fields) != 3 or len(rows) >= len(phases) or
                    fields[1] != phases[len(rows)] or re.fullmatch(r'0|[1-9][0-9]{0,18}', fields[2]) is None):
                raise ValueError('Invalid allocation checkpoint identity/order')
            value = int(fields[2])
            if value >= 1<<63:
                raise ValueError('Allocation counter out of range')
            rows.append(dict(phase=fields[1], occupied_bytes=value))
        else:
            # Existing duration/physical parsing retains all native identity, sentinel and correctness controls.
            finished = True
            ordinary.append(line)
    sample = parse_growth('\n'.join(ordinary), engine, count, steps, pattern, samples=1)[0]
    if len(rows) != len(phases):
        raise ValueError('Incomplete allocation checkpoint coverage')
    return dict(allocations=rows, physical={k: sample[k] for k in METRICS})
