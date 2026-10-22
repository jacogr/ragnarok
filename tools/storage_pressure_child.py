# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe one native child inside a fresh systemd unit; producers and outer orchestration stay outside."""
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time

from storage_limit_cgroup import resolve
from storage_pressure_metrics import read_raw, parse, derive, outcome

def child_setup(membership_log):
    """Prefer this disposable child as the unit OOM victim; never alter an ancestor's OOM policy."""
    Path('/proc/self/oom_score_adj').write_text('1000\n')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    # This same PID inherits its membership across exec even if it exits before parent sampling.
    adjustment = Path('/proc/self/oom_score_adj').read_text()
    if adjustment != '1000\n':
        raise ValueError('Native child must remain eligible for OOM selection')
    Path(membership_log).write_text(json.dumps(dict(
        membership_raw=Path('/proc/self/cgroup').read_text(),
        oom_score_adj_raw=adjustment, pid=os.getpid()))+'\n')


def observe(group, arguments, log, mounts):
    """Wait without pressure-time allocations; the kernel owns exact child/group RSS, swap and faults."""
    before_raw = read_raw(group)
    before = parse(before_raw)
    process = None
    timed_out = False
    started = time.monotonic()

    def stop_child(signum, frame):
        """The prearmed deadline sends only SIGKILL; no procfs reads or sampling allocations are needed."""
        nonlocal timed_out
        timed_out = True
        if process is not None and process.returncode is None:
            try:
                os.kill(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass  # Exit can win the exact deadline; wait4 still owns the final status.

    previous = signal.signal(signal.SIGALRM, stop_child)
    membership_log = Path(log).with_suffix('.membership.log')
    try:
        signal.alarm(35)
        with Path(log).open('w') as output:
            process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.STDOUT,
                                       preexec_fn=lambda: child_setup(membership_log))
            if timed_out:
                os.kill(process.pid, signal.SIGKILL)
            _, status, usage = os.wait4(process.pid, 0)
            process.returncode = os.waitstatus_to_exitcode(status)
    finally:
        # Restore the caller's signal ownership even after spawn/wait/log failures.
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)
        if process is not None and process.returncode is None:
            process.kill()
            _, status, _ = os.wait4(process.pid, 0)
            process.returncode = os.waitstatus_to_exitcode(status)
    after_raw = read_raw(group)
    evidence = derive(before, parse(after_raw))
    actual_outcome = outcome(process.returncode, evidence)
    deadline_fired = timed_out
    timed_out = timed_out and process.returncode == -9 and actual_outcome != 'local-cgroup-oom-kill'
    identity_raw = membership_log.read_text()
    child_identity = json.loads(identity_raw)
    membership = child_identity['membership_raw']
    if (child_identity['pid'] != process.pid or child_identity['oom_score_adj_raw'] != '1000\n' or
            resolve(membership, mounts) != str(group)):
        raise ValueError('Invalid native child OOM/cgroup identity receipt')
    return dict(arguments=arguments, before_raw=before_raw, after_raw=after_raw,
                evidence=evidence, timed_out=timed_out, deadline_fired=deadline_fired,
                outcome='observer-timeout' if timed_out else actual_outcome,
                exit_code=process.returncode, child_membership_raw=membership,
                child_pid=process.pid, child_identity_raw=identity_raw,
                elapsed_seconds=time.monotonic()-started,
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
    observer_adjustment = Path('/proc/self/oom_score_adj').read_text()
    if observer_adjustment != '-1000\n':
        raise ValueError('Observer must be immune to OOM selection before running a constrained child')
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
                  observer_oom_score_adj_raw=observer_adjustment,
                  address_space_limit=list(resource.getrlimit(resource.RLIMIT_AS)), runs=[])
    path = Path(target)
    path.write_text(json.dumps(report, indent=2)+'\n')
    try:
        if arguments == ['probe']:
            # The positive worker touches one MiB; the bounded negative worker touches up to96 MiB.
            code = 'import sys,time; n=int(sys.argv[1]); b=bytearray(n); b[::4096]=bytes([91])*len(b[::4096]); time.sleep(.1); print("touched",n,flush=True)'
            for name, size in (('positive', 1024*1024), ('negative', 96*1024*1024)):
                row = observe(group, [sys.executable, '-c', code, str(size)], path.with_name(name+'.log'), mounts)
                report['runs'].append(row)
                path.write_text(json.dumps(report, indent=2)+'\n')
            if report['runs'][0]['outcome'] != 'completed' or report['runs'][1]['outcome'] != 'local-cgroup-oom-kill':
                raise ValueError('Private cgroup did not establish bounded positive/negative controls')
        else:
            # Native output is interpreted by the outer workload parser; this observer owns OS evidence.
            row = observe(group, arguments, path.with_suffix('.native.log'), mounts)
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
