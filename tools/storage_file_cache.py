#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare validated read-only synthetic file scans under unchanged cache policy and explicit per-file hints."""
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import sys
import tempfile
from storage_benchmark import atomic_text, source_hashes
from storage_cache_hint import cache_hint, validate_hint
from storage_environment import environment
from storage_resource_panel import ROOT, CHILD
from pvm_reference import command

BLOCK = 65536
SIZES = (16777216, 67108864)
CASES = tuple((index, size, policy) for index, order in enumerate((('unchanged', 'hint'), ('hint', 'unchanged')))
              for policy in order for size in SIZES)
BODY = bytes(range(256))*256


def block(index):
    """Fixed block identities allow bounded independent read validation without retaining the file in memory."""
    return index.to_bytes(8, 'little')+BODY[8:]


def prepare(path, size):
    """Exclusively create and synchronize one deterministic fixture before fresh reader processes start."""
    if size not in SIZES:
        raise ValueError('Unknown file-cache fixture extent')
    digest = hashlib.sha256()
    with Path(path).open('xb') as stream:
        for index in range(size//BLOCK):
            # Only one fixed-size block is live; full-file payloads never enter parent or child heap.
            payload = block(index)
            if stream.write(payload) != len(payload):
                raise OSError('Incomplete file-cache fixture write')
            digest.update(payload)
        stream.flush(); os.fsync(stream.fileno())
    return digest.hexdigest()


def scan(path, size, policy):
    """Read one regular no-follow descriptor with bounded progress; advice never proves cache eviction."""
    if size not in SIZES or policy not in ('unchanged', 'hint'):
        raise ValueError('Unknown file-cache scan plan')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        before = os.fstat(descriptor)
        if before.st_size != size:
            raise ValueError('File-cache fixture size differs')
        start = resource.getrusage(resource.RUSAGE_SELF)
        hint = cache_hint(descriptor, policy); digest = hashlib.sha256(); calls = 0
        for index in range(size//BLOCK):
            # Short reads advance within one bounded block; zero progress before the known end refuses.
            payload = bytearray()
            while len(payload) < BLOCK:
                part = os.read(descriptor, BLOCK-len(payload)); calls += 1
                if not part:
                    raise ValueError('Truncated file-cache fixture')
                payload.extend(part)
            if payload != block(index):
                raise ValueError('File-cache fixture payload differs')
            digest.update(payload)
        finish = resource.getrusage(resource.RUSAGE_SELF); after = os.fstat(descriptor)
        identity = lambda st: (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns)
        if identity(before) != identity(after):
            raise ValueError('File-cache fixture changed during scan')
        return dict(bytes=size, read_calls=calls, sha256=digest.hexdigest(), hint=hint,
                    minor_faults=finish.ru_minflt-start.ru_minflt, major_faults=finish.ru_majflt-start.ru_majflt)
    finally:
        os.close(descriptor)


def validate_scan(value, size, policy, digest):
    """Logical read work, complete content identity and actual hint receipts remain independently visible."""
    if (type(value) is not dict or set(value) != {'bytes', 'read_calls', 'sha256', 'hint', 'minor_faults', 'major_faults'} or
            type(value['bytes']) is not int or value['bytes'] != size or value['sha256'] != digest or
            any(type(value[k]) is not int or not 0 <= value[k] < 1<<63 for k in ('read_calls', 'minor_faults', 'major_faults')) or
            not size//BLOCK <= value['read_calls'] <= size):
        raise ValueError('Invalid file-cache scan evidence')
    validate_hint(value['hint'], policy)
    return value


def inputs():
    """Freeze local observer/scan sources and the actual Python executable, without native speed provenance claims."""
    sources = [Path(__file__), ROOT/'tools/storage_cache_hint.py', ROOT/'tools/storage_environment.py', CHILD,
               ROOT/'tools/pvm_reference.py', ROOT/'tools/storage_benchmark.py', ROOT/'Makefile']
    return dict(sources=source_hashes(sources), python_version=platform.python_version(),
                python_sha256=hashlib.sha256(Path(sys.executable).read_bytes()).hexdigest(), platform=platform.platform())


def run():
    """Own synchronized fixtures, fresh reader resource observers, explicit hint availability and atomic results."""
    folder = ROOT/'build/tests/storage-file-cache'; folder.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'summary.md'):
        (folder/name).unlink(missing_ok=True)
    report = dict(status='running', schema_version=1, rows=[], checks=[], inputs=inputs(), environment=environment(folder))
    def save():
        """Failed/interrupted scans retain raw receipts but cannot leave a previous successful table."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')
    save()
    try:
        with tempfile.TemporaryDirectory(prefix='fixtures-', dir=folder) as owned:
            paths = {size: Path(owned)/str(size) for size in SIZES}
            digests = {size: prepare(paths[size], size) for size in SIZES}
            for index, size, policy in CASES:
                # The observer excludes parent fixture preparation from child process peak RSS and faults.
                counters = Path(owned)/f'{index}-{size}-{policy}.json'
                check = command([sys.executable, CHILD, counters, sys.executable, Path(__file__), '--child', paths[size], size, policy],
                                f'{index}-{size}-{policy}', folder, timeout=120)
                report['checks'].append(check); save()
                if check['exit_code'] != 0:
                    raise RuntimeError('File-cache scan failed: '+check['log'])
                raw = Path(check['log']).read_text(); value = validate_scan(json.loads(raw), size, policy, digests[size])
                report['rows'].append(dict(case=[index, size, policy], raw=raw, observed=value,
                                           resources=json.loads(counters.read_text()))); save()
        if inputs() != report['inputs']:
            raise RuntimeError('File-cache scan inputs changed')
        lines = ['# Synthetic file-cache observations', '',
                 'Per-file advice records requests only; it does not establish cold caches or physical device reads.',
                 'Read-interval faults include hint calls, hashing and full-byte validation. Child peak RSS includes Python startup.', '',
                 '| Pass | Bytes | Policy | Hint status | Interface | Logical read calls |', '| ---: | ---: | --- | --- | --- | ---: |']
        for row in report['rows']:
            index, size, policy = row['case']; value = row['observed']; hint = value['hint']
            lines.append(f'| {index} | {size} | {policy} | {hint["status"]} | {hint["interface"]} | {value["read_calls"]} |')
        report['status'] = 'checks-passed'
        atomic_text(folder/'summary.md', '\n'.join(lines)+'\n'); save()
        print('PASS file-cache observations: '+str(folder/'summary.md'))
    except Exception as error:
        report.update(status='failed', error=str(error)); (folder/'summary.md').unlink(missing_ok=True); save()
        raise


# Child stdout contains only one admitted JSON observation; the parent owns setup and failure publication.
if __name__ == '__main__':
    if len(sys.argv) == 5 and sys.argv[1] == '--child':
        print(json.dumps(scan(sys.argv[2], int(sys.argv[3]), sys.argv[4])))
    else:
        run()
