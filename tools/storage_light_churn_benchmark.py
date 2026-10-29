#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure fixed light-file evidence churn with isolated producers, fresh RSS observers and strict raw witnesses."""
import argparse
import hashlib
import json
import platform
import re
import statistics
import subprocess
import sys
from pathlib import Path
from native_checks import NativeChecks, ROOT
from native_preparation import prepare_libraries
from setup_nimony import installed
from storage_limit_receipts import validate_limit

SOURCE = ROOT/'tests/performance/storage_light_publication_workload.nim'
SIZES = (64, 1024)
FIELDS = ('size', 'cycles', 'image_bytes', 'written_bytes', 'writes', 'syncs', 'renames',
          'update_hashes', 'reopen_hashes', 'update_ns', 'reopen_ns', 'baseline',
          'retained_before', 'retained_after', 'retired')


def parse(raw, size):
    """Admit exact full-image work and ARC retirement before any timing or memory summary."""
    lines = raw.splitlines()
    fields = lines[0].split('\t') if len(lines) == 1 else []
    if (size not in SIZES or len(fields) != 1+len(FIELDS) or fields[0] != 'churn'
            or any(re.fullmatch(r'0|[1-9][0-9]{0,18}', value) is None for value in fields[1:])):
        raise ValueError('Invalid light churn output')
    row = dict(zip(FIELDS, map(int, fields[1:])))
    image = 128+4096*(41+17*64+size)
    expected = dict(size=size, cycles=8, image_bytes=image,
                    written_bytes=8*(2*image-(41+17*64+size)), writes=16, syncs=32,
                    renames=16, update_hashes=160, reopen_hashes=73729)
    if (any(row[key] != value for key, value in expected.items())
            or any(value >= 1<<63 for value in row.values()) or row['retired'] != row['baseline']
            or row['retained_before'] <= row['baseline'] or row['retained_after'] <= row['baseline']):
        raise ValueError('Invalid light churn work or lifetime')
    return row


def admit(raw, size, receipt, final_digest, expected_digest):
    """A successful launcher alone cannot authorize native success or changed selected bytes."""
    if (type(receipt) is not dict or type(receipt.get('exit_code')) is not int
            or receipt['exit_code'] != 0):
        raise ValueError('Native churn child failed')
    validate_limit(receipt.get('limit'), None)
    counters = receipt.get('resources')
    if (type(counters) is not dict or set(counters) != {'peak_rss_bytes', 'minor_faults', 'major_faults'}
            or any(type(v) is not int or not 0 <= v < 1<<63 for v in counters.values())
            or counters['peak_rss_bytes'] <= 0 or counters['peak_rss_bytes'] >= 1<<63
            or re.fullmatch('[0-9a-f]{64}', expected_digest or '') is None
            or final_digest != expected_digest):
        raise ValueError('Invalid churn memory or selected bytes')
    return parse(raw, size)


def digest(path):
    """Bind binary, source and selected files to their exact bytes, outside native RSS observations."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def identities():
    """Freeze storage/codec/crypto, native observer and workload/pin inputs without touching unrelated modules."""
    paths = [SOURCE, Path(__file__), ROOT/'spec/toolchain.json', ROOT/'spec/crypto-pins.json',
             ROOT/'tests/support/storage_io.nim', ROOT/'tests/nimony_crypto.py',
             ROOT/'tools/storage_io_observer.py']
    paths.extend(ROOT/'tools'/name for name in ['native_checks.py', 'native_preparation.py',
        'setup_nimony.py', 'storage_limit_child.py', 'storage_limit_exec.py',
        'storage_limit_receipts.py', 'storage_limit_budget.py'])
    for folder, pattern in [('src/storage', '*.nim'), ('src/codec', '*.nim'), ('src/crypto', '*.nim'),
                            ('native/storage_io', '*.[ch]')]:
        paths.extend(sorted((ROOT/folder).rglob(pattern)))
    return {str(path.relative_to(ROOT)): digest(path) for path in paths}


def summarize(report):
    """Report repeated baseline medians and ranges without inferring cold-cache or physical-device behavior."""
    if report.get('status') != 'checks-passed' or report.get('samples') not in (3, 5, 10):
        raise ValueError('Incomplete churn panel')
    cases = [(sample, size) for sample in range(report['samples'])
             for size in (SIZES if sample%2 == 0 else tuple(reversed(SIZES)))]
    if [(r['sample'], r['size']) for r in report['runs']] != cases:
        raise ValueError('Missing or duplicate churn samples')
    for row in report['runs']:
        expected = report['fixtures'][str(row['size'])]['sha256']
        if admit(row['raw'], row['size'], row['receipt'], row['final_sha256'], expected) != row['observed']:
            raise ValueError('Derived churn observations differ from raw evidence')
    lines = ['# Light-file churn baseline', '',
             'Eight one-key forget/admit pairs per fresh consumer; producer memory is excluded.', '',
             '| Value bytes | Completed write bytes | Update ms median (min–max) | Reopen ms median | Peak RSS MiB median |',
             '| ---: | ---: | ---: | ---: | ---: |']
    for size in SIZES:
        rows = [row for row in report['runs'] if row['size'] == size]
        updates = [row['observed']['update_ns']/1e6 for row in rows]
        reopen = [row['observed']['reopen_ns']/1e6 for row in rows]
        rss = [row['receipt']['resources']['peak_rss_bytes']/1048576 for row in rows]
        lines.append(f"| {size} | {rows[0]['observed']['written_bytes']} | {statistics.median(updates):.3f} ({min(updates):.3f}–{max(updates):.3f}) | {statistics.median(reopen):.3f} | {statistics.median(rss):.3f} |")
    lines += ['', 'Write extents are exact completed application writes, not physical device traffic. ',
              'RSS covers load, initialization, updates, reopen and validation; phase times cover only the named work. ',
              'No cold-cache, Linux pressure or power-loss claim. This is a baseline, not a speedup comparison.', '']
    return '\n'.join(lines)


def run(folder, samples):
    """One checked build produces both fixed fixtures and serial, independently accounted native consumers."""
    folder = Path(folder).resolve()
    if samples not in (3, 5, 10) or not folder.is_relative_to(ROOT/'build'):
        raise ValueError('Use 3/5/10 samples and an output directory under build/')
    folder.mkdir(parents=True, exist_ok=False)
    compiler, _ = installed()
    source_ids = identities()
    report = dict(status='running', sources=source_ids, samples=samples, runs=[], checks=[],
                  platform=platform.platform(), machine=platform.machine(), python=sys.version,
                  python_executable=sys.executable, compiler=str(compiler),
                  compiler_sha256=digest(compiler), head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip())
    def save():
        """Preserve failure status and raw witnesses; summaries appear only after the full panel passes."""
        (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        checks = NativeChecks(folder)
        libraries, _, _ = prepare_libraries(folder, required={'observer', 'storage_io'})
        cflags = ['-I'+str(ROOT/'native/storage_io'), '-include'+str(ROOT/'native/storage_io/redirect.h'),
                  '-DRAGNAROK_STORAGE_IO_WRITE', '-DRAGNAROK_STORAGE_IO_FSYNC', '-DRAGNAROK_STORAGE_IO_RENAMEAT']
        built, binary = checks.build(compiler, SOURCE, 'light-churn', crypto_library=libraries['observer'],
                                      cflags=cflags, link_flags=[str(libraries['storage_io'])])
        report['checks'].append(built); save()
        if built['exit_code'] != 0:
            raise RuntimeError('Native build failed')
        report['binary_sha256'] = digest(binary)
        report['native_libraries'] = {name: digest(path) for name, path in libraries.items()}
        report['fixtures'] = {}
        fixtures = {}
        for size in SIZES:
            # Each fixture has its own independent producer; no producer runs inside a measured child.
            source = folder/('source-'+str(size))
            produced = checks.command([binary, 'produce', size, source], 'produce-'+str(size))
            report['checks'].append(produced); save()
            if produced['exit_code'] != 0:
                raise RuntimeError('Fixture producer failed')
            root, extent = produced['output'].strip().split('\t')
            if re.fullmatch('[0-9a-f]{64}', root) is None or int(extent) != 128+4096*(41+17*64+size):
                raise ValueError('Invalid independent fixture identity')
            fixtures[size] = (source, root, digest(source/'CURRENT'))
            report['fixtures'][str(size)] = dict(root=root, bytes=int(extent), sha256=fixtures[size][2]); save()
        for sample in range(samples):
            # Alternate fixture order across rounds; every command gets a new process and exclusive destination.
            for size in SIZES if sample%2 == 0 else tuple(reversed(SIZES)):
                source, root, expected = fixtures[size]
                label = str(size)+'-'+str(sample)
                target = folder/('target-'+label)
                receipt_path = folder/('receipt-'+label+'.json')
                child = checks.command([sys.executable, ROOT/'tools/storage_limit_child.py', receipt_path, '0', '--',
                                        binary, 'churn', size, source, root, target], 'churn-'+label)
                report['checks'].append(child); save()
                if child['exit_code'] != 0:
                    raise RuntimeError('Churn observer failed')
                receipt = json.loads(receipt_path.read_text())
                observed = admit(child['output'], size, receipt, digest(target/'CURRENT'), expected)
                report['runs'].append(dict(size=size, sample=sample, raw=child['output'], observed=observed,
                                            receipt=receipt, final_sha256=expected)); save()
                for name in ['CURRENT', 'LOCK']:
                    (target/name).unlink()  # Exact files belong to this retired native child; preserve all failure artifacts.
                target.rmdir()
        if (source_ids != identities() or report['compiler_sha256'] != digest(compiler)
                or report['binary_sha256'] != digest(binary)
                or report['native_libraries'] != {name: digest(path) for name, path in libraries.items()}):
            raise ValueError('Measurement inputs changed')
        report['status'] = 'checks-passed'; save()
        (folder/'summary.md').write_text(summarize(report))
    except Exception as error:
        # Incomplete panels retain full evidence and never leave a successful summary.
        report.update(status='failed', error=str(error)); save()
        (folder/'summary.md').unlink(missing_ok=True)
        raise
    print('PASS light churn baseline: '+str(folder/'summary.md'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--samples', type=int, choices=(3, 5, 10), default=5)
    options = parser.parse_args()
    run(options.output, options.samples)
