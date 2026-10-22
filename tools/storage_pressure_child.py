# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe one native child inside a fresh systemd unit; producers and outer orchestration stay outside."""
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

from storage_limit_cgroup import resolve
from storage_limit_status import parse_status
from storage_pressure_metrics import read_raw, parse, derive, outcome

def child_setup():
    """Prefer this disposable child as the unit OOM victim; never alter an ancestor's OOM policy."""
    Path('/proc/self/oom_score_adj').write_text('1000\n')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def sample_status(raw):
    """Missing transition-time Vm fields are unavailable samples; malformed kernel rows still fail."""
    try:
        return parse_status(raw)
    except ValueError as error:
        if str(error) == 'Incomplete process memory status':
            return None
        raise


def observe(group, arguments, log):
    """wait4 owns exact child RSS/faults/block operations; sampled gauges are explicitly approximate."""
    before_raw = read_raw(group)
    before = parse(before_raw)
    peaks = dict(rss=0, swap=0, anon=0, file=0, cgroup_swap=0)
    samples = 0
    membership = None
    timed_out = False
    started = time.monotonic()
    with Path(log).open('w') as output:
        process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.STDOUT,
                                   preexec_fn=child_setup)
        try:
            while True:
                # Nonblocking wait4 preserves final child rusage without Popen.poll reaping it first.
                pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid:
                    process.returncode = os.waitstatus_to_exitcode(status)
                    break
                if time.monotonic()-started > 35:
                    # Even missing proc samples must obey the native observation deadline.
                    timed_out = True
                    process.kill()
                    _, status, usage = os.wait4(process.pid, 0)
                    process.returncode = os.waitstatus_to_exitcode(status)
                    break
                try:
                    raw_member = Path(f'/proc/{process.pid}/cgroup').read_text()
                    status_raw = Path(f'/proc/{process.pid}/status').read_text()
                except FileNotFoundError:
                    # The exact final counters still come from wait4 when exit races procfs.
                    time.sleep(0.002)
                    continue
                actual = resolve(raw_member, Path('/proc/self/mountinfo').read_text())
                if actual != str(group):
                    raise ValueError('Native child escaped its private cgroup')
                membership = raw_member
                memory = sample_status(status_raw)
                if memory is None:
                    # Exec/exit can temporarily remove Vm fields while State still reports running.
                    time.sleep(0.002)
                    continue
                current = parse(read_raw(group))
                peaks['rss'] = max(peaks['rss'], memory['VmRSS'])
                peaks['swap'] = max(peaks['swap'], memory['VmSwap'])
                peaks['anon'] = max(peaks['anon'], current['memory.stat']['anon'])
                peaks['file'] = max(peaks['file'], current['memory.stat']['file'])
                peaks['cgroup_swap'] = max(peaks['cgroup_swap'], current['memory.swap.current'])
                samples += 1
                time.sleep(0.02)
        finally:
            if process.returncode is None:
                # The unit's RuntimeMaxSec is an independent backstop if the outer runner is killed.
                process.kill()
                _, status, _ = os.wait4(process.pid, 0)
                process.returncode = os.waitstatus_to_exitcode(status)
    after_raw = read_raw(group)
    evidence = derive(before, parse(after_raw))
    if membership is None:
        raise ValueError('No live native cgroup membership witness')
    return dict(arguments=arguments, before_raw=before_raw, after_raw=after_raw,
                evidence=evidence, timed_out=timed_out,
                outcome='observer-timeout' if timed_out else outcome(process.returncode, evidence),
                exit_code=process.returncode, sampled_peaks=peaks if samples else None, samples=samples,
                child_membership_raw=membership, elapsed_seconds=time.monotonic()-started,
                resources=dict(peak_rss_bytes=usage.ru_maxrss*1024,
                               minor_faults=usage.ru_minflt, major_faults=usage.ru_majflt,
                               input_blocks=usage.ru_inblock, output_blocks=usage.ru_oublock),
                native_raw=Path(log).read_text())


def run(unit, target, high, maximum, swap, arguments):
    """Only the exact new unit may contain the observer; verify limits before starting native work."""
    membership = Path('/proc/self/cgroup').read_text()
    mounts = Path('/proc/self/mountinfo').read_text()
    group = Path(resolve(membership, mounts))
    if group.name != unit or not unit.startswith('ragnarok-storage-pressure-'):
        raise ValueError('Expected an exclusively owned transient service')
    initial_raw = read_raw(group)
    initial = parse(initial_raw)
    if (initial['memory.high'], initial['memory.max'], initial['memory.swap.max']) != (high, maximum, swap):
        raise ValueError('Resident-memory controls were not applied exactly')
    if group.joinpath('cgroup.procs').read_text().split() != [str(os.getpid())]:
        raise ValueError('Pressure unit already contains unrelated processes')
    ancestors = []
    parent = group.parent
    while (parent/'memory.max').exists():
        # Read ancestor limits only; stricter shared bounds remain visible and are never raised.
        ancestors.append(dict(path=str(parent), maximum=(parent/'memory.max').read_text(),
                              high=(parent/'memory.high').read_text()))
        parent = parent.parent
    report = dict(status='running', unit=unit, group=str(group), membership_raw=membership,
                  mountinfo_raw=mounts, initial_raw=initial_raw, ancestors=ancestors,
                  address_space_limit=list(resource.getrlimit(resource.RLIMIT_AS)), runs=[])
    path = Path(target)
    path.write_text(json.dumps(report, indent=2)+'\n')
    try:
        if arguments == ['probe']:
            # The positive worker touches one MiB; the bounded negative worker touches up to96 MiB.
            code = 'import sys,time; n=int(sys.argv[1]); b=bytearray(n); b[::4096]=bytes([91])*len(b[::4096]); time.sleep(.1); print("touched",n,flush=True)'
            for name, size in (('positive', 1024*1024), ('negative', 96*1024*1024)):
                row = observe(group, [sys.executable, '-c', code, str(size)], path.with_name(name+'.log'))
                report['runs'].append(row)
                path.write_text(json.dumps(report, indent=2)+'\n')
            if report['runs'][0]['outcome'] != 'completed' or report['runs'][1]['outcome'] != 'local-cgroup-oom-kill':
                raise ValueError('Private cgroup did not establish bounded positive/negative controls')
        else:
            # Native output is interpreted by the outer workload parser; this observer owns OS evidence.
            row = observe(group, arguments, path.with_suffix('.native.log'))
            report['runs'].append(row)
        report['status'] = 'observed'
    except Exception as error:
        report.update(status='failed', error=str(error))
        raise
    finally:
        path.write_text(json.dumps(report, indent=2)+'\n')


# Service launch is explicit; imports never allocate pressure workers or modify cgroup settings.
if __name__ == '__main__':
    from storage_limit_cgroup import scalar
    if len(sys.argv) < 8 or sys.argv[6] != '--':
        raise SystemExit('Expected unit, receipt, high, max, swap and child command')
    bounds = [scalar(value+'\n', True) for value in sys.argv[3:6]]
    run(sys.argv[1], sys.argv[2], *bounds, sys.argv[7:])
