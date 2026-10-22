#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure strict reopen in a fresh native consumer, excluding producer fixture construction from its resources."""
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
from build_crypto import dependencies, build_native
from native_checks import NativeChecks
from setup_nimony import installed
from storage_benchmark import atomic_text
from storage_resource_panel import ROOT, CHILD, panel_identity
from storage_environment import environment, validate_environment
from storage_resource_validation import validate_inputs, validate_build, validate_counters, validate_checks, digest
from pvm_reference import command

SOURCE = ROOT/'tests/performance/storage_fresh_reopen.nim'
CASES = tuple((engine, count) for engine in ('journal', 'managed') for count in (32768, 131072))


def selected_hashes(path):
    """Hash only this synthetic producer's closed namespace; strict consumer open must preserve every byte."""
    paths = [path] if path.is_file() else sorted(path.iterdir())
    if any(p.is_symlink() or not p.is_file() for p in paths):
        raise ValueError('Unexpected fresh-reopen namespace member')
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def parse_prepared(output, engine, count):
    """The exact root token comes only from a successful separately completed producer process."""
    fields = output.strip().split('\t')
    if len(fields) != 6 or fields[:5] != ['prepared', engine, str(count), '16', '17'] or re.fullmatch('[0-9a-f]{64}', fields[5]) is None:
        raise ValueError('Invalid fresh-reopen producer witness')
    return fields[5]


def parse_reopened(output, engine, count, root):
    """Require the consumer's exact expected root, complete-map checks and allocator release witnesses."""
    fields = output.strip().split('\t')
    if (len(fields) != 12 or fields[:6] != ['reopened', engine, str(count), '16', '17', root] or
            any(re.fullmatch(r'0|[1-9][0-9]{0,18}', v) is None for v in fields[6:])):
        raise ValueError('Invalid fresh-reopen consumer identity')
    row = dict(zip(('stored_nodes', 'baseline', 'opened_bytes', 'closed_bytes', 'released', 'checks'), map(int, fields[6:])))
    if (any(v >= 1<<63 for v in row.values()) or not count*2-1 <= row['stored_nodes'] <= 600000 or
            row['opened_bytes'] <= row['baseline'] or row['closed_bytes'] <= row['baseline'] or
            row['released'] != row['baseline'] or row['checks'] != count*2):
        raise ValueError('Invalid fresh-reopen consumer witnesses')
    return row


def validate_report(report):
    """Reparse both native processes and require exact command/root/namespace/counter coverage."""
    if (type(report) is not dict or report.get('status') != 'checks-passed' or report.get('schema_version') != 2 or
            type(report.get('schema_version')) is not int or report.get('error') or not digest(report.get('native_binary_sha256'))):
        raise ValueError('Invalid fresh-reopen report status/schema')
    validate_inputs(report.get('inputs'), SOURCE); validate_environment(report.get('environment'))
    checks = validate_checks(report.get('checks'), 1+2*len(CASES)); binary = validate_build(checks[0], SOURCE, ())
    rows = report.get('rows')
    if type(rows) is not list or len(rows) != len(CASES):
        raise ValueError('Incomplete fresh-reopen cases')
    for index, (engine, count) in enumerate(CASES):
        row = rows[index]; prepared = checks[1+index*2]['command']; consumed = checks[2+index*2]['command']
        if type(row) is not dict or row.get('case') != [engine,count] or type(row.get('raw')) is not str or type(row.get('prepared_raw')) is not str:
            raise ValueError('Invalid fresh-reopen case')
        root = parse_prepared(row['prepared_raw'],engine,count)
        if root != row.get('root') or json.dumps(parse_reopened(row['raw'],engine,count,root),sort_keys=True) != json.dumps(row.get('observed'),sort_keys=True):
            raise ValueError('Substituted fresh-reopen observations')
        if len(prepared) != 5 or prepared[:4] != [binary,'prepare',engine,str(count)]:
            raise ValueError('Invalid fresh-reopen producer command')
        owned = prepared[4]
        if consumed != [report['inputs']['python_identity']['executable'],str(CHILD),str(Path(owned)/'resources.json'),binary,'open',engine,str(count),owned,root]:
            raise ValueError('Invalid fresh-reopen consumer command')
        expected = {'store'} if engine == 'journal' else {'CURRENT','LOCK','journal-0000000000000001.wal','snapshot-0000000000000001.bin'}
        before = row.get('selected_before'); after = row.get('selected_after')
        if type(before) is not dict or set(before) != expected or before != after or any(not digest(v) for v in before.values()):
            raise ValueError('Invalid strict fresh-reopen byte preservation')
        validate_counters(row.get('resources'))
    return rows


def run():
    """Build once, close each producer, observe one fresh consumer, and retain exact byte-preservation receipts."""
    folder = ROOT/'build/tests/storage-fresh-reopen'; folder.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'summary.md'):
        (folder/name).unlink(missing_ok=True)
    report = dict(status='running', schema_version=2, checks=[], rows=[], environment=environment(folder))
    def save():
        """Partial native receipts stay inspectable without retaining a stale successful table."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')
    save()
    try:
        compiler, _ = installed(); library = build_native(dependencies(False))
        report['inputs'] = panel_identity(compiler, library, SOURCE)
        build, binary = NativeChecks(folder).build(compiler, SOURCE, 'reopen-native', crypto_library=library)
        build.pop('output', None); report['checks'].append(build); save()
        if build['exit_code'] != 0:
            raise RuntimeError('Fresh reopen build failed: '+build['log'])
        report['native_binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        for engine, count in CASES:
            with tempfile.TemporaryDirectory(prefix=engine+'-', dir=folder) as owned:
                # Producer setup is independently checked and never contributes consumer peak RSS or faults.
                prepared = command([binary, 'prepare', engine, count, owned], f'prepare-{engine}-{count}', folder, timeout=300)
                report['checks'].append(prepared); save()
                if prepared['exit_code'] != 0:
                    raise RuntimeError('Fresh reopen producer failed: '+prepared['log'])
                prepared_raw = Path(prepared['log']).read_text()
                root = parse_prepared(prepared_raw, engine, count)
                before = selected_hashes(Path(owned)/'store'); counters = Path(owned)/'resources.json'
                consumed = command([sys.executable, CHILD, counters, binary, 'open', engine, count, owned, root],
                                   f'open-{engine}-{count}', folder, timeout=300)
                report['checks'].append(consumed); save()
                if consumed['exit_code'] != 0:
                    raise RuntimeError('Fresh reopen consumer failed: '+consumed['log'])
                raw = Path(consumed['log']).read_text(); observed = parse_reopened(raw, engine, count, root)
                after = selected_hashes(Path(owned)/'store')
                if before != after:
                    raise ValueError('Strict fresh reopen changed selected file bytes')
                report['rows'].append(dict(case=[engine, count], root=root, prepared_raw=prepared_raw, raw=raw, observed=observed,
                    selected_before=before, selected_after=after, resources=json.loads(counters.read_text())))
            save()
        if panel_identity(compiler, library, SOURCE) != report['inputs'] or hashlib.sha256(binary.read_bytes()).hexdigest() != report['native_binary_sha256']:
            raise RuntimeError('Fresh reopen inputs changed')
        lines = ['# Fresh-process strict reopen', '',
                 'Producer fixture construction is excluded from consumer resources. The OS cache remains alive.',
                 'Exact producer roots, complete-map checks and byte-identical selected files remain mandatory.', '',
                 '| Backend | Entries | Open Nim bytes | Consumer peak RSS bytes |', '| --- | ---: | ---: | ---: |']
        for row in report['rows']:
            engine, count = row['case']
            lines.append(f'| {engine} | {count} | {row["observed"]["opened_bytes"]} | {row["resources"]["peak_rss_bytes"]} |')
        report['status'] = 'checks-passed'; validate_report(report); atomic_text(folder/'summary.md', '\n'.join(lines)+'\n'); save()
        print('PASS fresh native reopen panel: '+str(folder/'summary.md'))
    except Exception as error:
        report.update(status='failed', error=str(error)); (folder/'summary.md').unlink(missing_ok=True); save()
        raise


# Imports expose token and native-evidence validators without preparing a namespace.
if __name__ == '__main__':
    run()
