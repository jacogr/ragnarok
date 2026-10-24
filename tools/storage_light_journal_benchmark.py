#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare matched light-image and journal churn with strict raw work, lifetime and fresh-child resource receipts."""
import argparse
import json
import platform
import re
import statistics
import subprocess
import sys
from pathlib import Path
import storage_light_churn_benchmark as baseline
from native_checks import NativeChecks, ROOT
from native_preparation import prepare_libraries
from setup_nimony import installed
from storage_limit_receipts import validate_limit

MODES = ('churn', 'journal')
BATCH_MODES = MODES+('journal-batch',)


def valid_digest(value):
    """Namespace identities must be exact lowercase SHA-256 strings, never null or scalar substitutes."""
    return type(value) is str and re.fullmatch('[0-9a-f]{64}', value) is not None


def parse(raw, size, mode):
    """Require exact predetermined work; journal bytes come from sixteen canonical single-edit frame extents."""
    if mode == 'churn':
        return baseline.parse(raw, size)
    lines = raw.splitlines()
    fields = lines[0].split('\t') if len(lines) == 1 else []
    if (mode not in ('journal', 'journal-batch') or size not in baseline.SIZES or len(fields) != 1+len(baseline.FIELDS)
            or fields[0] != mode or any(re.fullmatch(r'0|[1-9][0-9]{0,18}', v) is None for v in fields[1:])):
        raise ValueError('Invalid matched journal output')
    row = dict(zip(baseline.FIELDS, map(int, fields[1:])))
    expected = dict(size=size, cycles=8, image_bytes=128+4096*(1129+size),
                    written_bytes=8*(500+1088+size), writes=1 if mode == 'journal-batch' else 16,
                    syncs=1 if mode == 'journal-batch' else 16, renames=0,
                    update_hashes=176, reopen_hashes=73907)
    if (any(row[k] != v for k, v in expected.items()) or any(v >= 1<<63 for v in row.values())
            or row['retired'] != row['baseline'] or row['retained_before'] <= row['baseline']
            or row['retained_after'] <= row['baseline']):
        raise ValueError('Invalid matched journal work or retirement')
    return row


def admit(raw, size, mode, receipt, image_digest, expected_digest):
    """Admit actual native exit, unchanged inherited limits, resources and exact final proof-image transport."""
    if mode == 'churn':
        return baseline.admit(raw, size, receipt, image_digest, expected_digest)
    if (type(receipt) is not dict or type(receipt.get('exit_code')) is not int
            or receipt['exit_code'] != 0):
        raise ValueError('Native journal child failed')
    validate_limit(receipt.get('limit'), None)
    counters = receipt.get('resources')
    if (type(counters) is not dict or set(counters) != {'peak_rss_bytes', 'minor_faults', 'major_faults'}
            or any(type(v) is not int or not 0 <= v < 1<<63 for v in counters.values())
            or counters['peak_rss_bytes'] <= 0 or re.fullmatch('[0-9a-f]{64}', expected_digest or '') is None
            or image_digest != expected_digest):
        raise ValueError('Invalid journal resources or checkpoint bytes')
    return parse(raw, size, mode)


def cases(samples, modes=MODES):
    """Alternate both backend and value-size order across independent fresh-process rounds."""
    if not isinstance(modes, (tuple, list)) or tuple(modes) not in (MODES, BATCH_MODES):
        raise ValueError('Invalid matched backend set')
    modes = tuple(modes)
    return [(sample, size, mode) for sample in range(samples)
            for size in (baseline.SIZES if sample%2 == 0 else tuple(reversed(baseline.SIZES)))
            for mode in (modes if sample%2 == 0 else tuple(reversed(modes)))]


def summarize(report):
    """Re-admit the complete paired panel before reporting observed medians or deterministic write reductions."""
    if report.get('status') != 'checks-passed' or report.get('samples') not in (3, 5, 10):
        raise ValueError('Incomplete matched panel')
    modes = report.get('modes', MODES)
    if [(r['sample'], r['size'], r['mode']) for r in report['runs']] != cases(report['samples'], modes):
        raise ValueError('Missing or duplicate matched consumer')
    for row in report['runs']:
        expected = report['fixtures'][str(row['size'])]['sha256']
        if admit(row['raw'], row['size'], row['mode'], row['receipt'], row['image_sha256'], expected) != row['observed']:
            raise ValueError('Derived observations differ from raw evidence')
        expected_length = row['observed']['written_bytes']+98 if row['mode'] != 'churn' else 0
        if (type(row['journal_bytes']) is not int or row['journal_bytes'] != expected_length
                or not valid_digest(row['current_sha256'])
                or (row['mode'] != 'churn' and not valid_digest(row['journal_sha256']))):
            raise ValueError('Selected namespace extent or identity mismatch')
    lines = ['# Matched light evidence churn', '',
             'Identical 4,096-query fixtures; eight one-key forget/admit pairs per fresh consumer.', '',
             '| Value bytes | Backend | Completed write bytes | Syncs | Renames | Update ms median (min–max) | Reopen ms median | Peak RSS MiB median |',
             '| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for size in baseline.SIZES:
        for mode in modes:
            rows = [r for r in report['runs'] if r['size'] == size and r['mode'] == mode]
            updates = [r['observed']['update_ns']/1e6 for r in rows]
            reopen = [r['observed']['reopen_ns']/1e6 for r in rows]
            rss = [r['receipt']['resources']['peak_rss_bytes']/1048576 for r in rows]
            first = rows[0]['observed']
            lines.append(f"| {size} | {mode} | {first['written_bytes']} | {first['syncs']} | {first['renames']} | {statistics.median(updates):.3f} ({min(updates):.3f}–{max(updates):.3f}) | {statistics.median(reopen):.3f} | {statistics.median(rss):.3f} |")
    lines += ['', 'Application write extents exclude initialization and differ from device traffic. ',
              'Both modes retain the same pre-edit reader and strictly reauthenticate the final image. ',
              'Journal reopen also authenticates all sixteen frames; compaction and cleanup are excluded. ',
              'RSS includes load, initialization, updates, reopen and validation. Producer RSS is excluded. ',
              'Times are observed on this host; no cold-cache, Linux pressure, hardware power-loss or general speedup claim.', '']
    return '\n'.join(lines)


def identities():
    """Include the shared baseline driver plus this paired orchestration in frozen source identities."""
    result = baseline.identities()
    result[str(Path(__file__).relative_to(ROOT))] = baseline.digest(__file__)
    return result


def run(folder, samples, include_batch=False):
    """One checked binary and two separate producers supply serial paired consumers with fresh resource observers."""
    folder = Path(folder).resolve()
    if samples not in (3, 5, 10) or not folder.is_relative_to(ROOT/'build'):
        raise ValueError('Use 3/5/10 rounds under build/')
    folder.mkdir(parents=True, exist_ok=False)
    compiler, _ = installed()
    source_ids = identities()
    modes = BATCH_MODES if include_batch else MODES
    report = dict(status='running', sources=source_ids, samples=samples, modes=modes, runs=[], checks=[], fixtures={},
                  platform=platform.platform(), machine=platform.machine(), compiler=str(compiler),
                  compiler_sha256=baseline.digest(compiler), python=sys.version,
                  head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip())
    def save():
        """Keep incomplete evidence observable; successful summaries require the full frozen panel."""
        (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        checks = NativeChecks(folder)
        libraries, _, _ = prepare_libraries(folder, required={'observer', 'storage_io'})
        cflags = ['-I'+str(ROOT/'native/storage_io'), '-include'+str(ROOT/'native/storage_io/redirect.h'),
                  '-DRAGNAROK_STORAGE_IO_WRITE', '-DRAGNAROK_STORAGE_IO_FSYNC', '-DRAGNAROK_STORAGE_IO_RENAMEAT']
        built, binary = checks.build(compiler, baseline.SOURCE, 'matched-light-churn', crypto_library=libraries['observer'],
                                      cflags=cflags, link_flags=[str(libraries['storage_io'])])
        report['checks'].append(built); save()
        if built['exit_code'] != 0:
            raise RuntimeError('Matched native build failed')
        report['binary_sha256'] = baseline.digest(binary)
        report['native_libraries'] = {n: baseline.digest(p) for n, p in libraries.items()}
        fixtures = {}
        for size in baseline.SIZES:
            # Independent fixture generation is outside every consumer's process and resource receipt.
            source = folder/('source-'+str(size))
            produced = checks.command([binary, 'produce', size, source], 'produce-'+str(size))
            report['checks'].append(produced); save()
            if produced['exit_code'] != 0:
                raise RuntimeError('Independent producer failed')
            root, extent = produced['output'].strip().split('\t')
            if re.fullmatch('[0-9a-f]{64}', root) is None or int(extent) != 128+4096*(1129+size):
                raise ValueError('Invalid fixture extent/root')
            fixtures[size] = (source, root)
            report['fixtures'][str(size)] = dict(root=root, bytes=int(extent), sha256=baseline.digest(source/'CURRENT')); save()
        for sample, size, mode in cases(samples, modes):
            # Every backend/size/round receives one new namespace and one independently accounted native child.
            source, root = fixtures[size]
            label = f'{mode}-{size}-{sample}'
            target = folder/('target-'+label)
            receipt_path = folder/('receipt-'+label+'.json')
            child = checks.command([sys.executable, ROOT/'tools/storage_limit_child.py', receipt_path, '0', '--',
                                    binary, mode, size, source, root, target], label)
            report['checks'].append(child); save()
            if child['exit_code'] != 0:
                raise RuntimeError('Matched consumer observer failed')
            receipt = json.loads(receipt_path.read_text())
            image = target/('CURRENT' if mode == 'churn' else 'snapshot-0000000000000001.bin')
            observed = admit(child['output'], size, mode, receipt, baseline.digest(image), report['fixtures'][str(size)]['sha256'])
            journal = target/'journal-0000000000000001.wal'
            report['runs'].append(dict(sample=sample, size=size, mode=mode, raw=child['output'], observed=observed,
                receipt=receipt, image_sha256=baseline.digest(image), current_sha256=baseline.digest(target/'CURRENT'),
                journal_sha256=baseline.digest(journal) if mode != 'churn' else None,
                journal_bytes=journal.stat().st_size if mode != 'churn' else 0)); save()
            for name in (['CURRENT', 'LOCK'] if mode == 'churn' else
                         ['CURRENT', 'LOCK', 'snapshot-0000000000000001.bin', 'journal-0000000000000001.wal']):
                (target/name).unlink()  # Exact owned retired fixture files only; failed runs retain all artifacts.
            target.rmdir()
        if (source_ids != identities() or report['compiler_sha256'] != baseline.digest(compiler)
                or report['binary_sha256'] != baseline.digest(binary)
                or report['native_libraries'] != {n: baseline.digest(p) for n, p in libraries.items()}):
            raise ValueError('Matched measurement inputs changed')
        report['status'] = 'checks-passed'
        summary = summarize(report)
        save(); (folder/'summary.md').write_text(summary)
    except Exception as error:
        # Partial/failing panels preserve raw evidence and cannot leave successful summaries.
        report.update(status='failed', error=str(error)); save()
        (folder/'summary.md').unlink(missing_ok=True)
        raise
    print('PASS matched light churn: '+str(folder/'summary.md'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--samples', type=int, choices=(3, 5, 10), default=5)
    parser.add_argument('--include-batch', action='store_true', help='Also compare one-barrier prepared journal updates')
    options = parser.parse_args()
    run(options.output, options.samples, options.include_batch)
