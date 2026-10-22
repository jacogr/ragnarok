#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure complete native reopens under private cgroup memory pressure, retaining attributed raw evidence."""
import csv
import io
import json
import os
from pathlib import Path
import platform
import stat
import sys
import tempfile

from build_crypto import build_native, dependencies
from native_checks import NativeChecks
from pvm_reference import command
from setup_nimony import installed
from storage_benchmark import atomic_text
from storage_environment import environment
from storage_fresh_reopen import parse_prepared, parse_reopened
from storage_limit_host import snapshot
from storage_limit_namespace import fingerprint
from storage_limit_provenance import ROOT, SOURCE, identity, validate_identity
from storage_resource_validation import validate_checks, validate_build
from storage_pressure_scope import execute, validate_receipt
from storage_pressure_metrics import parse

BUILD = ROOT/'build/tests/storage-resident-pressure'
MIB = 1024*1024
CASES = tuple((backend, count) for backend in ('journal', 'managed') for count in (32768, 131072))
TREATMENTS = (('high128-max512', (128*MIB, 512*MIB, 0)),
              ('max128-noswap', (128*MIB, 128*MIB, 0)),
              ('max256-noswap', (128*MIB, 256*MIB, 0)),
              ('max256-swap256', (128*MIB, 256*MIB, 256*MIB)))
CONTROL = (None, None, 0)


def swap_context(raw):
    """Read existing host swap only; allowance is unavailable unless256 MiB is currently free."""
    lines = raw.splitlines()
    if not lines or lines[0].split() != ['Filename', 'Type', 'Size', 'Used', 'Priority']:
        raise ValueError('Invalid host swap header')
    free = 0
    for line in lines[1:]:
        fields = line.split()
        if len(fields) != 5 or not fields[2].isdecimal() or not fields[3].isdecimal():
            raise ValueError('Invalid host swap row')
        size, used = int(fields[2]), int(fields[3])
        if used > size:
            raise ValueError('Invalid host swap usage')
        free += (size-used)*1024
    return dict(raw=raw, free_bytes=free, permitted=free >= 256*MIB)


def evict_owned(path, backend):
    """Advise eviction only for this closed synthetic namespace; syscall success never proves cold IO."""
    members = [path] if backend == 'journal' else sorted(path.iterdir())
    expected = {'store'} if backend == 'journal' else {'CURRENT', 'LOCK',
                'journal-0000000000000001.wal', 'snapshot-0000000000000001.bin'}
    if path.is_symlink() or backend not in ('journal', 'managed') or {p.name for p in members} != expected:
        raise ValueError('Unexpected owned eviction namespace')
    rows = []
    for member in members:
        # Fingerprinting already established the exact allowlisted set; no symlink or special file is admitted.
        fd = os.open(member, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or not 0 <= before.st_size <= 256*MIB:
                raise ValueError('Unexpected eviction-advice target')
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
            after = os.fstat(fd)
            if (before.st_dev, before.st_ino, before.st_size) != (after.st_dev, after.st_ino, after.st_size):
                raise ValueError('Eviction-advice target changed')
            rows.append(dict(name=member.name, size=before.st_size, device=before.st_dev,
                             inode=before.st_ino, advice='POSIX_FADV_DONTNEED'))
        finally:
            os.close(fd)
    return rows


def preflight(folder=BUILD):
    """Fail unsupported hosts before native setup, proving bounded positive and local-OOM controls."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    (folder/'preflight.json').unlink(missing_ok=True)
    if platform.system() != 'Linux':
        raise RuntimeError('Resident-pressure experiments require Linux, systemd and private cgroup v2')
    result = execute(['probe'], (64*MIB, 64*MIB, 0), folder, 'enforcement-probe')
    rows = result['observed']['runs']
    if len(rows) != 2 or [r['outcome'] for r in rows] != ['completed', 'local-cgroup-oom-kill']:
        raise ValueError('Incomplete resident-limit enforcement proof')
    atomic_text(folder/'preflight.json', json.dumps(result, indent=2)+'\n')
    print('PASS isolated64 MiB positive/negative enforcement and service cleanup', flush=True)
    return result


def validate(report):
    """Reparse exact raw native/kernel receipts and require all cases, passes, treatments and controls."""
    if report.get('status') != 'checks-passed' or report.get('schema_version') != 1:
        raise ValueError('Invalid resident-pressure report status')
    validate_identity(report['identity'])
    checks = validate_checks(report['checks'], 1+2*len(CASES))
    if validate_build(checks[0], SOURCE, ()) != report['binary']:
        raise ValueError('Substituted resident-pressure binary')
    probe = report['preflight']
    parsed_probe = json.loads(probe['receipt_raw'])
    if parsed_probe != probe['observed']:
        raise ValueError('Substituted enforcement probe')
    validate_receipt(parsed_probe, parsed_probe['unit'], (64*MIB, 64*MIB, 0))
    if [r['outcome'] for r in parsed_probe['runs']] != ['completed', 'local-cgroup-oom-kill']:
        raise ValueError('Missing resident-limit enforcement proof')
    planned = []
    for turn in range(2):
        # Reverse both work and treatment order; controls still bracket each independently produced namespace.
        cases = CASES if turn == 0 else tuple(reversed(CASES))
        treatments = TREATMENTS if turn == 0 else tuple(reversed(TREATMENTS))
        for backend, count in cases:
            planned.extend((turn, backend, count, name, bounds) for name, bounds in
                           (('before', CONTROL), *treatments, ('after', CONTROL)))
    rows = report['rows']
    if len(rows) != len(planned):
        raise ValueError('Incomplete resident-pressure plan')
    binary = report['binary']
    for row, (turn, backend, count, name, bounds) in zip(rows, planned):
        if (row['pass'], row['backend'], row['count'], row['name'], tuple(row['bounds'])) != (turn, backend, count, name, bounds):
            raise ValueError('Substituted pressure case/order')
        if row['selected_before'] != row['selected_after']:
            raise ValueError('Pressure attempt changed selected bytes')
        root = parse_prepared(row['prepared_raw'], backend, count)
        if root != row['root']:
            raise ValueError('Substituted pressure root')
        if row['outcome'] == 'unavailable':
            if name != 'max256-swap256' or swap_context(row['swap']['raw'])['permitted'] or row.get('execution'):
                raise ValueError('Unproven unavailable swap treatment')
            continue
        execution = row['execution']
        receipt = json.loads(execution['receipt_raw'])
        if receipt != execution['observed']:
            raise ValueError('Substituted raw service receipt')
        validate_receipt(receipt, receipt['unit'], bounds)
        if len(receipt['runs']) != 1 or receipt['address_space_limit'] != [-1, -1]:
            raise ValueError('Unexpected observer plan or inherited address-space cap')
        observed = receipt['runs'][0]
        if observed['arguments'] != [binary, 'open', backend, str(count), row['owned'], root] or observed['outcome'] != row['outcome']:
            raise ValueError('Substituted native command/outcome')
        if row['outcome'] == 'completed':
            if parse_reopened(observed['native_raw'], backend, count, root) != row['native']:
                raise ValueError('Substituted successful native witnesses')
        elif name in ('before', 'after'):
            raise ValueError('Failed unrestricted pressure control')
        if execution['cleanup']['state'] not in ('inactive', 'failed'):
            raise ValueError('Missing service retirement')
    return rows


def table_row(row):
    """Unavailable rows stay empty; completed, killed and timed-out rows keep distinct measured counters."""
    values = dict(pass_index=row['pass'], backend=row['backend'], entries=row['count'],
                  treatment=row['name'], outcome=row['outcome'])
    if row['outcome'] == 'unavailable':
        return values
    observed = row['execution']['observed']['runs'][0]
    after = parse(observed['after_raw'])
    peaks = observed['sampled_peaks'] or dict(anon=None, file=None, cgroup_swap=None, swap=None)
    values.update(opened_nim_bytes=row['native']['opened_bytes'] if row['outcome'] == 'completed' else None,
                  closed_nim_bytes=row['native']['closed_bytes'] if row['outcome'] == 'completed' else None,
                  released_nim_bytes=row['native']['released'] if row['outcome'] == 'completed' else None,
                  rss_bytes=observed['resources']['peak_rss_bytes'],
                  cgroup_peak_bytes=after['memory.peak'],
                  sampled_anon_bytes=peaks['anon'],
                  sampled_file_bytes=peaks['file'],
                  sampled_swap_bytes=peaks['cgroup_swap'],
                  sampled_process_swap_bytes=peaks['swap'],
                  high_events=observed['evidence']['events']['high'],
                  oom_kills=observed['evidence']['events']['oom_kill'],
                  pgscan=observed['evidence']['reclaim']['pgscan'],
                  pgsteal=observed['evidence']['reclaim']['pgsteal'],
                  full_stall_us=observed['evidence']['stalls_us']['full'],
                  major_faults=observed['resources']['major_faults'],
                  input_blocks=observed['resources']['input_blocks'],
                  io_device_bytes=json.dumps(observed['evidence']['io'], sort_keys=True),
                  seconds=round(observed['elapsed_seconds'], 6))
    return values


def publish(report, folder):
    """Publish only a validated complete plan; timings remain descriptive, not a speed comparison."""
    rows = [table_row(row) for row in validate(report)]
    fields = list(dict.fromkeys(key for row in rows for key in row))
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
    atomic_text(folder/'observations.csv', stream.getvalue())
    lines = ['# Controlled resident-memory pressure', '',
             'Private cgroup limits include observer, kernel and file-cache charges; child RSS is separate.',
             'Eviction is per-file advice. Block counters cover native loader/storage activity, not latency.',
             'Swap permission alone is not paging evidence. Sampled maxima may miss brief peaks.',
             'All successful rows require exact roots/maps/lifetimes; all selected bytes remain unchanged.',
             'Two passes reverse case/treatment order. Seconds are observations, not a speedup claim.', '',
             '| Pass | Backend | Entries | Treatment | Outcome | Open Nim MiB | Child RSS MiB | Unit peak MiB | Swap sampled MiB | High events | OOM kills | Full stall ms | Input blocks |',
             '| ---: | --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for row in rows:
        # Explicit unavailability must never render as measured zero-resource success.
        if row['outcome'] == 'unavailable':
            cells = ['—']*8
        else:
            cells = [f"{row['opened_nim_bytes']/MIB:.1f}" if row['opened_nim_bytes'] is not None else '—',
                     f"{row['rss_bytes']/MIB:.1f}", f"{row['cgroup_peak_bytes']/MIB:.1f}",
                     f"{row['sampled_swap_bytes']/MIB:.1f}" if row['sampled_swap_bytes'] is not None else '—',
                     str(row['high_events']),
                     str(row['oom_kills']), f"{row['full_stall_us']/1000:.1f}", str(row['input_blocks'])]
        lines.append('| '+' | '.join(map(str, [row['pass_index'], row['backend'], row['entries'],
                                               row['treatment'], row['outcome'], *cells]))+' |')
    atomic_text(folder/'summary.md', '\n'.join(lines)+'\n')


def run(folder=BUILD):
    """Build one unchanged native binary and collect bounded two-pass pressure observations atomically."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'summary.md', 'observations.csv'):
        # Failed/unsupported runs must retire prior successful public artifacts.
        (folder/name).unlink(missing_ok=True)
    report = dict(status='running', schema_version=1, rows=[], checks=[])

    def save():
        """Partial raw receipts remain reviewable when a failed control prevents summary publication."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')

    save()
    try:
        report['preflight'] = preflight(folder)
        report['environment'] = environment(folder)
        report['context_before'] = snapshot()
        compiler, _ = installed()
        library = build_native(dependencies(False))
        build, binary = NativeChecks(folder).build(compiler, SOURCE, 'resident-native', crypto_library=library)
        build.pop('output', None)
        report['checks'].append(build)
        if build['exit_code'] != 0:
            raise RuntimeError('Resident-pressure native build failed: '+build['log'])
        report['binary'] = str(binary)
        report['identity'] = identity(compiler, library, binary)
        for turn in range(2):
            cases = CASES if turn == 0 else tuple(reversed(CASES))
            treatments = TREATMENTS if turn == 0 else tuple(reversed(TREATMENTS))
            for backend, count in cases:
                with tempfile.TemporaryDirectory(prefix=f'p{turn}-{backend}-', dir=folder) as owned:
                    # Producers run outside measured units and close before any consumer starts.
                    label = f'p{turn}-{backend}-{count}'
                    prepared = command([binary, 'prepare', backend, count, owned], 'prepare-'+label, folder, timeout=300)
                    report['checks'].append(prepared)
                    if prepared['exit_code'] != 0:
                        raise RuntimeError('Resident-pressure producer failed')
                    raw = Path(prepared['log']).read_text()
                    root = parse_prepared(raw, backend, count)
                    for name, bounds in (('before', CONTROL), *treatments, ('after', CONTROL)):
                        before = fingerprint(Path(owned)/'store', backend)
                        swap = swap_context(Path('/proc/swaps').read_text())
                        row = dict(pass_index=turn, backend=backend, count=count, name=name,
                                   bounds=list(bounds), owned=owned, root=root, prepared_raw=raw,
                                   selected_before=before, swap=swap)
                        row['pass'] = row.pop('pass_index')
                        if name == 'max256-swap256' and not swap['permitted']:
                            row.update(outcome='unavailable', reason='insufficient-existing-free-swap')
                        else:
                            # Hashing may warm cache; advice comes afterward and is never called a cold-cache proof.
                            row['advice'] = evict_owned(Path(owned)/'store', backend)
                            args = [str(binary), 'open', backend, str(count), owned, root]
                            execution = execute(args, bounds, folder, label+'-'+name)
                            row['execution'] = execution
                            observed = execution['observed']['runs'][0]
                            row['outcome'] = observed['outcome']
                            if observed['outcome'] == 'completed':
                                row['native'] = parse_reopened(observed['native_raw'], backend, count, root)
                            elif name in ('before', 'after'):
                                raise RuntimeError('Unrestricted resident-pressure control failed')
                        row['selected_after'] = fingerprint(Path(owned)/'store', backend)
                        report['rows'].append(row)
                        save()
                        if before != row['selected_after']:
                            raise ValueError('Resident-pressure attempt changed selected bytes')
                        print(label+' '+name+': '+row['outcome'], flush=True)
        report['context_after'] = snapshot()
        if identity(compiler, library, binary) != report['identity']:
            raise RuntimeError('Resident-pressure source/build inputs changed')
        report['status'] = 'checks-passed'
        validate(report)
        save()
        publish(report, folder)
        print('PASS resident-pressure evidence: '+str(folder/'results.json'))
        return report
    except Exception as error:
        report.update(status='failed', error=str(error))
        for name in ('summary.md', 'observations.csv'):
            (folder/name).unlink(missing_ok=True)
        save()
        raise


# A standalone preflight performs no native setup; the Make panel owns compiler provisioning.
if __name__ == '__main__':
    if sys.argv[1:] == ['--probe']:
        preflight()
    elif sys.argv[1:]:
        raise SystemExit('Expected no arguments or --probe')
    else:
        run()
