#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Audit immutable original regional census artifacts as inert data, never execute downloaded code."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'build/region-coverage-evidence/41059179556'
HEAD = '8bdaac76535552fad6c308374ba72d9cbb2604a2'
sys.path.insert(0, str(ROOT/'tools'))
from pvm_region_diagnostic import parse
from pvm_arm64_jit import qualify as qualify_arm
from pvm_x86_jit import qualify as qualify_x86


def sha(raw):
    """Identify inert original bytes."""
    return hashlib.sha256(raw).hexdigest()


def git(path):
    """Read exact immutable committed source only."""
    return subprocess.check_output(['git', 'show', HEAD+':'+path], cwd=ROOT)


def command_rows(value):
    """Find retained command records without conflating expected compile failures with runtime failures."""
    if isinstance(value, dict):
        if 'command' in value and 'exit_code' in value:
            yield value
        for child in value.values():
            yield from command_rows(child)
    elif isinstance(value, list):
        for child in value:
            yield from command_rows(child)


class Replay:
    """Replay maintained qualification predicates over actual logs; never launch their command arrays."""
    def __init__(self, report, extracted, architecture):
        self.extracted = extracted
        self.rows = {Path(row['log']).stem: row for row in command_rows(report) if 'log' in row}
        sample = next(iter(command_rows(report)))
        self.folder = Path(sample['command'][-1]).parent
        # Commands use original runner paths only as scalar identity, not filesystem execution authority.
        self.folder = Path('/home/runner/work/ragnarok/ragnarok/build/tests/pvm-native')
        self.architecture = architecture
        self.logs_without_returned_exit = []

    def command(self, args, name, **kwargs):
        """Return exact retained output; disclose successful commands whose status is only guaranteed by CI sequencing."""
        path = self.extracted/'tests/pvm-native'/(name+'.log')
        output = path.read_text()
        if name in self.rows:
            row = deepcopy(self.rows[name])
            if 'output' in row: assert row['output'] == output
            row['output'] = output
            return row
        self.logs_without_returned_exit.append(name)
        # Maintained qualifying code reaches report passed only after these explicit success checks.
        return dict(command=list(map(str, args)), exit_code=0, output=output,
                    log=str(path.relative_to(self.extracted)))

    def build(self, compiler, source, name, **kwargs):
        """Compilation is also inert; only recorded statuses/diagnostics can satisfy rejection controls."""
        row = self.command([], name+'-build')
        assert name+'-build' in self.rows, 'Missing actual recorded build status: '+name
        return row, self.folder/name


run = json.loads((BASE/'run.json').read_text())
for helper in ('tools/pvm_region_diagnostic.py', 'tools/pvm_arm64_jit.py', 'tools/pvm_x86_jit.py'):
    assert (ROOT/helper).read_bytes() == git(helper), 'Replay helpers must match the frozen source'
assert run['head_sha'] == HEAD and run['status'] == 'completed' and run['conclusion'] == 'success'
jobs = json.loads((BASE/'jobs.json').read_text())['jobs']
active = [job for job in jobs if job['conclusion'] != 'skipped']
assert len(active) == 2 and all(job['conclusion'] == 'success' for job in active)
assert all(next(step for step in job['steps'] if step['name'] ==
    'Observe bounded regional coverage without timings')['conclusion'] == 'success' for job in active)
listing = json.loads((BASE/'artifacts.json').read_text())['artifacts']
summary = {}
audits = {}
for architecture in ('arm64', 'x86_64'):
    name = 'pvm-comparison-'+architecture+'-1'
    artifact = next(row for row in listing if row['name'] == name)
    archive = BASE/(name+'.zip')
    assert archive.stat().st_size == artifact['size_in_bytes']
    assert 'sha256:'+sha(archive.read_bytes()) == artifact['digest']
    extracted = BASE/name
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        for member in bundle.infolist():
            if not member.is_dir():
                assert (extracted/member.filename).read_bytes() == bundle.read(member)
        payload_count = len(bundle.infolist())
    report = json.loads((extracted/'tests/pvm-region-diagnostic/results.json').read_text())
    gates = json.loads((extracted/'tests/pvm-native/results.json').read_text())
    assert report['revision'] == gates['revision'] == HEAD
    assert report['status'] == gates['status'] == 'passed'
    assert report['host']['architecture'] == gates['host']['architecture'] == architecture
    assert report['compiler_sha256'] == gates['compiler_sha256']
    for rows in (report['sources'], gates['sources']):
        for path, expected in rows.items():
            assert sha(git(path)) == expected, path
    negative_controls = report['doom_admission']['controls']
    assert {(row['engine'], row['control']) for row in negative_controls} == {
        (engine, kind) for engine in ('native', 'reference') for kind in ('assertions', 'state', 'output')}
    assert all(row['passed'] and row['run']['exit_code'] == (1 if row['engine'] == 'native' else 101)
        for row in negative_controls)
    expected_negative = {row['run']['log']: row['run']['exit_code'] for row in negative_controls}
    for row in command_rows(report):
        if 'log' in row and (extracted/row['log'].removeprefix('build/')).exists():
            raw = (extracted/row['log'].removeprefix('build/')).read_text()
            if 'output' in row: assert raw == row['output'], row['log']
        assert row['exit_code'] == expected_negative.get(row.get('log'), 0)
    replay = Replay(gates, extracted, architecture)
    qualified = qualify_arm(replay, Path('inert-compiler'), native=True) if architecture == 'arm64' else qualify_x86(replay, Path('inert-compiler'))
    assert len(qualified) == len(gates['qualification']) == (11 if architecture == 'arm64' else 15)
    assert len(gates['policy_qualification']) == 2
    for policy in gates['policy_qualification']:
        row = policy['run']
        assert row['exit_code'] == 0
        assert (extracted/row['log'].removeprefix('build/')).read_text() == row['output']
    images = {}
    for built in report['builds']:
        output = next(arg.split(':', 1)[1] for arg in built['command'] if arg.startswith('--out:'))
        path = extracted/'tests/pvm-region-diagnostic'/Path(output).name
        raw = path.read_bytes()
        assert sha(raw) == built['binary_sha256']
        assert raw[:7] == b'\x7fELF\x02\x01\x01'
        assert int.from_bytes(raw[18:20], 'little') == (183 if architecture == 'arm64' else 62)
        images[path.name] = sha(raw)
    assert len(images) == 7
    assert len(report['runs']) == 9
    rows = {(row['case'], row['role']): row for row in report['runs']}
    assert len(rows) == 9
    coverage = {}
    for case in ('init', 'tick', 'sieve'):
        for role in ('normal', 'diagnostic', 'refused'):
            row = rows[case, role]
            assert row['run']['exit_code'] == 0
            output = row['run']['output']
            assert 'DOOM_SAMPLE' not in output
            if case == 'sieve':
                samples = [line.split(',') for line in output.splitlines() if line.startswith('SIEVE,')]
                assert len(samples) == (1 if role == 'normal' else 2)
                assert all(sample[-2:] == ['0', '0'] for sample in samples)
            else:
                assert output.count('DOOM_OK,native,'+case+',') == 1
            if role == 'normal':
                assert row['receipts'] is None and 'REGION_DIAG' not in output
            else:
                parsed = parse(output)
                assert parsed == row['receipts']
                assert not any(sample['truncated'] for sample in parsed)
                if role == 'refused': assert not any(parsed[-1]['totals'].values())
                if role == 'diagnostic':
                    first, last = parsed
                    previous = {root['pc']: root for root in first['roots']}
                    candidates = [root for root in last['roots'] if root['occupied']]
                    coverage[case] = dict(
                        reused={key: last['totals'][key]-first['totals'][key] for key in last['totals']},
                        cold=first['totals'], occupancy=dict(status=last['status'], fragments=last['fragments'],
                            code_bytes=last['code_bytes'], published_header=last['published_header']),
                        roots=last['count'], dropped=last['dropped_visits'], incomplete=last['incomplete'],
                        published=[root for root in last['roots'] if root['published']],
                        independently_occupied_selfloops=[dict(pc=root['pc'], span=root['span'],
                            visits_reused=root['visits']-previous.get(root['pc'], {}).get('visits', 0),
                            closed1=root['closed1'], closed2=root['closed2'], closed3=root['closed3'],
                            conflicting_cycles=root['conflicting_cycles']) for root in candidates])
    summary[architecture] = coverage
    audits[architecture] = dict(artifact=artifact['id'], sha256=artifact['digest'], payloads=payload_count,
        diagnostic_sources=len(report['sources']), gate_sources=len(gates['sources']),
        qualification_rows=len(qualified), policy_rows=2, retained_ELF_images=images,
        successful_gate_commands_without_returned_exit_metadata=replay.logs_without_returned_exit)

assert summary['arm64']['tick']['reused'] == summary['x86_64']['tick']['reused'] == dict(calls=0, blocks=0, operations=0)
assert summary['arm64']['sieve']['reused'] == summary['x86_64']['sieve']['reused'] == dict(calls=5000000, blocks=19999997, operations=49999993)
occupied = summary['x86_64']['init']['independently_occupied_selfloops']
assert {row['pc'] for row in occupied} == {2947, 464624}
assert all(row['closed1'] and not row['closed2'] and not row['closed3'] and not row['conflicting_cycles'] for row in occupied)
assert sum(row['span']*row['visits_reused'] for row in occupied) == 10618
receipt = dict(status='author-inert-actual-audit-PASS-with-explicit-observer-limits', run=run['id'], revision=HEAD,
    artifacts=audits, diagnostic_native_calls_and_state='verified', source_eligibility_not_emitter_acceptance=True,
    observer_limit='Checked cycle history is not cleared across native-region returns; do not use cross-gap multi-block cycle attribution. Actual native counters, zero-region gameplay, and direct selfloop counts are independent of this history.',
    decision='FINAL REGROUP: no extra-slot or x86-residency runtime trial justified; no diagnostic expansion/re-run',
    native_artifact_execution=False, performance_claim=False)
(BASE/'coverage-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
(BASE/'author-audit.json').write_text(json.dumps(receipt, indent=2)+'\n')
files = {path.relative_to(BASE).as_posix(): sha(path.read_bytes()) for path in BASE.rglob('*')
    if path.is_file() and path.name != 'preservation.json'}
(BASE/'preservation.json').write_text(json.dumps(dict(files=files), indent=2)+'\n')
print(receipt['status'])
print('Official payloads', sum(row['payloads'] for row in audits.values()), 'ELFs', sum(len(row['retained_ELF_images']) for row in audits.values()))
print('Reused independently occupied x86 pure selfloop operations', 10618)
