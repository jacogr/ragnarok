# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Create only uniquely named transient services; enforce cleanup independently of command timeouts."""
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import uuid

from pvm_reference import command
from storage_limit_provenance import ROOT
from storage_pressure_metrics import parse, derive, outcome
from storage_limit_cgroup import resolve

CHILD = Path(__file__).with_name('storage_pressure_child.py')
PATTERN = r'ragnarok-storage-pressure-[0-9a-f]{32}\.service'


def validate_unit(unit):
    """Cleanup accepts only generated experiment identities, never a parent slice or external unit."""
    if type(unit) is not str or re.fullmatch(PATTERN, unit) is None:
        raise ValueError('Invalid owned pressure unit')


def launch_arguments(unit, target, high, maximum, swap, arguments):
    """Apply limits only to the new service and run its observer as the existing repository user."""
    validate_unit(unit)
    if any(v is not None and (type(v) is not int or not 0 <= v <= 512*1024*1024)
           for v in (high, maximum, swap)) or swap is None:
        raise ValueError('Invalid bounded pressure controls')
    value = lambda n: 'infinity' if n is None else str(n)
    child_value = lambda n: 'max' if n is None else str(n)
    return ['sudo', '-n', 'systemd-run', '--quiet', '--wait', '--pipe', '--collect',
            '--unit='+unit, '--uid='+str(os.getuid()), '--gid='+str(os.getgid()),
            '--working-directory='+str(ROOT), '--property=Type=exec',
            '--property=MemoryAccounting=yes', '--property=IOAccounting=yes',
            '--property=MemoryHigh='+value(high), '--property=MemoryMax='+value(maximum),
            '--property=MemorySwapMax='+value(swap), '--property=OOMPolicy=continue',
            '--property=RuntimeMaxSec=45', '--property=TimeoutStopSec=5',
            '--property=KillMode=control-group', '--property=LimitCORE=0',
            sys.executable, str(CHILD), unit, str(target), child_value(high),
            child_value(maximum), child_value(swap), '--', *[str(a) for a in arguments]]


def cleanup(unit):
    """Stop only this owned service, even after timeout; verify no active workload is left behind."""
    validate_unit(unit)
    stopped = subprocess.run(['sudo', '-n', 'systemctl', 'stop', unit], capture_output=True,
                             text=True, timeout=15)
    state = subprocess.run(['sudo', '-n', 'systemctl', 'show', unit, '--property=ActiveState', '--value'],
                           capture_output=True, text=True, timeout=15)
    if state.stdout.strip() not in ('inactive', 'failed'):
        raise RuntimeError('Pressure service cleanup did not establish inactivity')
    return dict(stop_exit=stopped.returncode, state=state.stdout.strip())


def validate_receipt(report, unit, bounds):
    """Reparse raw kernel evidence and reject substituted derived counters/outcomes or missing children."""
    validate_unit(unit)
    if report.get('status') != 'observed' or report.get('unit') != unit or not report.get('runs'):
        raise ValueError('Incomplete pressure receipt')
    group = report['group']
    if Path(group).name != unit or resolve(report['membership_raw'], report['mountinfo_raw']) != group:
        raise ValueError('Substituted observer cgroup identity')
    initial = parse(report['initial_raw'])
    if tuple(initial[k] for k in ('memory.high', 'memory.max', 'memory.swap.max')) != bounds:
        raise ValueError('Substituted pressure controls')
    for row in report['runs']:
        # Gauges are observed values; only the raw monotonic counters establish attributed events.
        before, after = parse(row['before_raw']), parse(row['after_raw'])
        if any(tuple(raw[k] for k in ('memory.high', 'memory.max', 'memory.swap.max')) != bounds
               for raw in (before, after)):
            raise ValueError('Cgroup controls changed during observation')
        if resolve(row['child_membership_raw'], report['mountinfo_raw']) != group:
            raise ValueError('Substituted native cgroup identity')
        if type(row['samples']) is not int or not 0 < row['samples'] <= 10000:
            raise ValueError('Missing bounded native sampling evidence')
        resources = row['resources']
        expected = {'peak_rss_bytes', 'minor_faults', 'major_faults', 'input_blocks', 'output_blocks'}
        if (type(resources) is not dict or set(resources) != expected or
                any(type(v) is not int or not 0 <= v < 1 << 63 for v in resources.values()) or
                resources['peak_rss_bytes'] == 0):
            raise ValueError('Invalid exact wait4 resources')
        evidence = derive(before, after)
        if evidence != row['evidence'] or outcome(row['exit_code'], evidence) != row['outcome']:
            raise ValueError('Substituted pressure observations')
    return report


def execute(arguments, bounds, folder, name):
    """An uncapped outer owner retains receipts and always stops its detached systemd service."""
    if platform.system() != 'Linux':
        raise RuntimeError('Resident-pressure qualification requires Linux cgroup v2 and systemd')
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    unit = 'ragnarok-storage-pressure-'+uuid.uuid4().hex+'.service'
    target = folder/(name+'.json')
    target.unlink(missing_ok=True)
    argv = launch_arguments(unit, target, *bounds, arguments)
    try:
        check = command(argv, name, folder, timeout=65)
    finally:
        # systemd services are not descendants of the outer timeout process group; explicit stop is mandatory.
        retired = cleanup(unit)
    if check['exit_code'] != 0:
        raise RuntimeError('Resident-pressure service failed: '+check['log'])
    raw = target.read_text()
    report = validate_receipt(json.loads(raw), unit, bounds)
    return dict(check=check, receipt_path=str(target), receipt_raw=raw,
                observed=report, cleanup=retired)
