# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Parse fresh, private cgroup-v2 memory/reclaim/IO receipts without confusing them with RSS."""
from pathlib import Path
import re
from storage_limit_budget import natural
from storage_limit_cgroup import scalar, events
from storage_limit_psi import parse_psi

FILES = ('memory.current', 'memory.peak', 'memory.high', 'memory.max',
         'memory.swap.current', 'memory.swap.max', 'memory.events.local',
         'memory.stat', 'memory.pressure', 'memory.oom.group', 'io.stat')


def counters(raw):
    """Kernel flat-key counters admit new fields, but never duplicate or malformed numeric values."""
    if type(raw) is not str or len(raw) > 65536:
        raise ValueError('Invalid pressure counter extent')
    result = {}
    for line in raw.splitlines():
        # Memory-stat keys include digits in kernel extensions; values stay canonical naturals.
        parts = line.split()
        if len(parts) != 2 or not parts[0].replace('_', '').isalnum() or parts[0] in result:
            raise ValueError('Invalid pressure counter row')
        result[parts[0]] = natural(parts[1])
    return result


def io_counters(raw):
    """Keep per-device block bytes/operations distinct; an empty device list is valid, not missing."""
    if type(raw) is not str or len(raw) > 65536:
        raise ValueError('Invalid cgroup IO extent')
    result = {}
    for line in raw.splitlines():
        parts = line.split()
        device = parts[0].split(':') if parts else []
        if len(device) != 2 or any(not v.isdecimal() for v in device) or parts[0] in result:
            raise ValueError('Invalid cgroup IO device')
        row = {}
        seen = set()
        base = {'rbytes', 'wbytes', 'rios', 'wios'}
        for field in parts[1:]:
            key, sep, value = field.partition('=')
            if not sep or key in seen or re.fullmatch('[a-z][a-z0-9_.]*', key) is None:
                raise ValueError('Invalid cgroup IO counter')
            seen.add(key)
            if key in base:
                row[key] = natural(value)
            # Optional latency/cost gauges remain in raw text; they are not monotonic byte counters.
        if not row:
            # blkcg_print_one_stat omits all four fields exactly when all four are zero.
            row = {key: 0 for key in base}
        elif set(row) != base:
            raise ValueError('Partial cgroup IO counters')
        result[parts[0]] = row
    return result


def read_raw(group):
    """Read only this verified unit's kernel files; failed or truncated observations fail qualification."""
    result = {}
    for name in FILES:
        # Fixed file names and bounded reads cannot traverse a caller-selected member path.
        with (Path(group)/name).open() as source:
            raw = source.read(65537)
        if len(raw) > 65536:
            raise ValueError('Oversized cgroup observation')
        result[name] = raw
    return result


def parse(raw):
    """Reparse the original text and require the stable fields needed for resident-pressure decisions."""
    if type(raw) is not dict or set(raw) != set(FILES):
        raise ValueError('Incomplete pressure snapshot')
    result = {}
    for name, value in raw.items():
        # Limits, events, PSI, device counters and byte/count statistics have separate contracts.
        if name == 'memory.events.local':
            result[name] = events(value)
        elif name == 'memory.stat':
            result[name] = counters(value)
            if not {'anon', 'file', 'pgfault', 'pgmajfault', 'pgscan', 'pgsteal'} <= result[name].keys():
                raise ValueError('Incomplete memory-stat observation')
        elif name == 'memory.pressure':
            result[name] = parse_psi(value)
        elif name == 'io.stat':
            result[name] = io_counters(value)
        else:
            result[name] = scalar(value, name in ('memory.high', 'memory.max', 'memory.swap.max'))
    if result['memory.oom.group'] != 0:
        raise ValueError('Group-wide OOM killing would destroy the observer')
    return result


def delta(before, after):
    """Only monotonic counters are subtracted; byte gauges and peaks are never presented as deltas."""
    result = {}
    for key in set(before) | set(after):
        # A previously unseen IO device starts at zero; disappearance or counter rollback is invalid.
        if key not in after or after[key] < before.get(key, 0):
            raise ValueError('Pressure counter disappeared or decreased')
        result[key] = after[key]-before.get(key, 0)
    return result


def derive(before, after):
    """Expose local OOM/reclaim/stall/IO evidence; SIGKILL without these counters stays unclassified."""
    devices = {}
    for device in set(before['io.stat']) | set(after['io.stat']):
        # Devices may first acquire charges during this native load/read; retain their raw identities.
        devices[device] = delta(before['io.stat'].get(device, {}), after['io.stat'].get(device, {}))
    stat_keys = ('pgfault', 'pgmajfault', 'pgscan', 'pgsteal')
    return dict(events=delta(before['memory.events.local'], after['memory.events.local']),
                reclaim=delta({k: before['memory.stat'][k] for k in stat_keys},
                              {k: after['memory.stat'][k] for k in stat_keys}),
                stalls_us=delta({k: before['memory.pressure'][k]['total'] for k in ('some', 'full')},
                                {k: after['memory.pressure'][k]['total'] for k in ('some', 'full')}),
                io=devices)


def outcome(code, evidence):
    """A private-unit local OOM event plus kill is stronger evidence than an unattributed signal."""
    if code == 0:
        return 'completed'
    if code == -9 and all(evidence['events'].get(key, 0) > 0 for key in ('max', 'oom', 'oom_kill')):
        return 'local-cgroup-oom-kill'
    return 'signal-unclassified' if code < 0 else 'nonzero-exit'
