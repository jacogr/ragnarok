#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Audit sealed DOOM CI outputs as inert bytes only; never execute retained images or downloaded code."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import zipfile

ROOT = Path('/Users/jacogr/Projects/jacogr/ragnarok-pvm-jit')
sys.path.insert(0, str(ROOT/'tools'))
import pvm_doom_e2e as h
from pvm_doom_attribution import tga_rgba

HEAD = 'fdd863842221f43497e21345d021d846d14042a5'
RUN = 41031037331
PREFIX = 'build/tests/pvm-doom-e2e/'


def sha(data):
    """Bind every comparison to bytes rather than a claimed filename or reconstructed VM field."""
    return hashlib.sha256(data).hexdigest()


def git(revision, path):
    """Read existing frozen Git source; no downloaded helper or executable is imported."""
    return subprocess.check_output(['git', 'show', revision+':'+path], cwd=ROOT)


class OracleView:
    """Read the complete retained oracle without copying RAM; normal results intentionally exclude trace files."""
    def __init__(self, folder, trace):
        self.folder, self.trace = folder, trace

    def __truediv__(self, name):
        # This view reparses policy receipts against complete oracle bytes, not unretained sample bytes.
        if name.endswith('.hosts') and not self.trace:
            return self.folder/('not-a-normal-output-'+name)
        return self.folder/name


def audit(folder):
    """Require exact run/source/build/ownership/state/gas/control/timing identities before accepting any ratio."""
    base = folder.parent
    dispatch = json.loads((base/'run.json').read_text())
    assert dispatch['id'] == RUN and dispatch['event'] == 'workflow_dispatch'
    assert dispatch['head_sha'] == HEAD
    archive = folder.with_suffix('.zip')
    meta = json.loads(archive.with_suffix('.json').read_text())
    assert meta['workflow_run']['id'] == RUN and meta['workflow_run']['head_sha'] == HEAD
    raw = archive.read_bytes()
    assert len(raw) == meta['size_in_bytes'] and 'sha256:'+sha(raw) == meta['digest']
    payloads = 0
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        for item in bundle.infolist():
            if item.is_dir():
                continue
            relative = Path(item.filename)
            assert not relative.is_absolute() and '..' not in relative.parts
            assert (folder/relative).read_bytes() == bundle.read(item)
            payloads += 1

    def retained(path):
        """Resolve only an ordinary retained build member, never a path supplied outside the archive."""
        assert path.startswith('build/') and '..' not in Path(path).parts
        result = folder/path.removeprefix('build/')
        assert result.is_file(), path
        return result

    def command(row):
        """Each scalar command receipt must equal its retained full stdout/stderr log."""
        assert retained(row['log']).read_text() == row['output']
        return row['command']

    d = json.loads(retained(PREFIX+'results.json').read_text())
    assert d['revision'] == HEAD and d['production'] == h.MASTER and d['experimental_eager'] == h.EAGER
    assert d['protocol'] == 'doom-immutable-caller-e2e-v1' and d['contract'] == h.CONTRACT
    complete = d['status'] == 'passed'
    if not complete:
        # This cancelled run retained all prerequisites and a strict cohort prefix, never a complete comparison.
        assert d['status'] == 'incomplete' and d['summary'] == []
        assert [(row['order'], row['batch'], row['sample'], row['role']) for row in d['runs']] == h.matrix()[:len(d['runs'])]
    arch = d['host']['architecture']
    assert meta['name'] == folder.name == f'pvm-doom-e2e-{arch}-1'
    machine = {'arm64':183, 'x86_64':62}[arch]
    assert (d['batches'], d['samples'], d['discarded'], d['role_order']) == ([1, 2, 8], 13, 3, list(h.ROLES))
    assert (d['expected_processes'], d['expected_calls']) == (312, 1144)
    assert sha(git(HEAD, 'tools/pvm_doom_e2e.py')) == d['identities']['tools/pvm_doom_e2e.py']
    for name, pin in d['pins'].items():
        assert json.loads(git(HEAD, 'spec/'+name)) == pin
    assert d['compiler']['sha256'] == d['identities'][d['compiler']['path']]
    command(d['rust_compiler'])
    command(d['cpu_details'])
    driver = h.native_projection(git(HEAD, 'tests/performance/pvm_doom_e2e.nim').decode()).encode()
    assert retained(PREFIX+'consumer.nim').read_bytes() == driver
    source_files = 0
    for endpoint, revision in (('production', h.MASTER), ('experimental', h.EAGER)):
        raw = subprocess.check_output(['git', 'archive', revision, 'src', 'native/pvm_jit'], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(raw)) as tree:
            expected = {m.name:tree.extractfile(m).read() for m in tree if m.isfile()}
        expected['benchmarks/doom.nim'] = driver
        assert set(expected) == set(d['source_maps'][endpoint])
        for name, data in expected.items():
            assert sha(data) == d['source_maps'][endpoint][name]
            source_files += 1

    def elf(path, wanted):
        """Inspect the ELF identity and actual native CPU header; never load or execute the image."""
        data = path.read_bytes()
        assert sha(data) == wanted and data[:7] == b'\x7fELF\x02\x01\x01' and len(data) >= 64
        assert int.from_bytes(data[16:18], 'little') in (2, 3)
        assert int.from_bytes(data[18:20], 'little') == machine

    assert len(d['builds']) == 6
    seen = set()
    for build in d['builds']:
        key = (build['endpoint'], build['repeat'], build['trace'])
        assert key not in seen
        seen.add(key)
        row = build['run']
        assert row['exit_code'] == 0
        args = command(row)
        assert args[1] == 'c' and args[-1].endswith('/snapshot/benchmarks/doom.nim')
        for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
                     '--passC:-flto=thin', '--passL:-flto=thin', '--passL:-fuse-ld=lld', '--passC:-D_GNU_SOURCE'):
            assert flag in args
        definitions = ['release', 'pvmArm64Jit' if arch == 'arm64' else 'pvmX86Jit', 'pvmArm64JitOwnerReceipt']
        if build['trace']:
            definitions += ['pvmSourceSealingReceipt', 'pvmDoomE2eTrace']
        assert [arg[3:] for arg in args if arg.startswith('-d:')] == definitions
        assert not any('danger' in arg or 'checks:off' in arg or 'polkavmRuntime' in arg for arg in args)
        name = 'trace-'+build['endpoint'] if build['trace'] else build['endpoint']+'-'+str(build['repeat'])
        elf(retained(PREFIX+name), d['trace_images'][build['endpoint']] if build['trace'] else d['images'][build['endpoint']])
    assert seen == {(endpoint, repeat, trace) for endpoint in ('production', 'experimental')
                    for repeat, trace in ((0, False), (1, False), (0, True))}
    for endpoint in ('production', 'experimental', 'reference'):
        left, right = (retained(PREFIX+endpoint+'-'+str(i)) for i in (0, 1))
        assert left.read_bytes() == right.read_bytes()
        elf(left, d['images'][endpoint])
    elf(retained(PREFIX+'trace-reference-0'), d['trace_images']['reference'])
    preflight = json.loads((ROOT/'build/pvm-doom-e2e-evidence/41028220399'/folder.name/
        'tests/pvm-doom-e2e/results.json').read_text())
    for endpoint in ('production', 'experimental'):
        # Require the actual cohort normal/trace binaries to equal the independently inspected preflight.
        assert d['images'][endpoint] == preflight['images'][endpoint]
        assert d['trace_images'][endpoint] == preflight['trace_images'][endpoint]
    for trace, key in ((False, 'reference_sources'), (True, 'trace_reference_sources')):
        ref = d[key]
        assert ref['backend'] == 'Interpreter' and not ref['step_tracing'] and not ref['dynamic_paging']
        assert ref['fresh_instance_each_call'] and ref['immutable_adapter'] and ref['trace'] == trace
        assert ref['rustflags'] == '--check-cfg=cfg(pvm_doom_e2e_trace)'+(' --cfg=pvm_doom_e2e_trace' if trace else '')
        assert len(ref['builds']) == (1 if trace else 2)
        for row in ref['builds']:
            assert row['exit_code'] == 0
            args = command(row)
            assert all(flag in args for flag in ('--release', '--locked', '--offline'))
        for path, wanted in ref['original'].items():
            assert sha(git(HEAD, path)) == wanted
        for path, wanted in ref['projected'].items():
            assert sha(retained(path).read_bytes()) == wanted
        prefix = PREFIX+('trace-reference' if trace else 'reference')+'-source/'
        projected = h.reference_projection(git(HEAD, 'tests/performance/polkavm_doom/src/main.rs').decode(),
            git(HEAD, 'tests/performance/pvm_doom_e2e_ref.rs.inc').decode()).encode()
        assert retained(prefix+'src/main.rs').read_bytes() == projected
        assert retained(prefix+'Cargo.lock').read_bytes() == git(HEAD, 'tests/performance/polkavm_doom/Cargo.lock')

    inputs = {}
    input_root = folder/'tests/pvm-doom-e2e/retained-inputs'
    for path in input_root.rglob('*'):
        if path.is_file():
            name = path.relative_to(input_root).as_posix()
            inputs[name] = path.read_bytes()
            assert sha(inputs[name]) == d['identities'][name]
    prepared = 'build/tests/pvm-doom/prepared/'
    initial, first = inputs[prepared+'tick.input'], inputs[prepared+'tick.expected']
    catalog = h.fixture_catalog(initial)
    assert catalog == [tuple(row) for row in d['catalog']]
    wire, pages = int.from_bytes(initial[8:12], 'little'), len(catalog)
    assert first[:8] == b'PVMDOME1' and len(first) == 120+pages*4096
    canonical = bytearray(b'PVME2E01'+b'\x03'+bytes(8)+first[8:16]+bytes(8)+b'\x01'+first[16:120]+pages.to_bytes(4, 'little'))
    for page in range(pages):
        at = 152+wire+page*4101
        canonical += initial[at:at+5]+first[120+page*4096:120+(page+1)*4096]
    oracle = folder/'tests/pvm-doom-e2e/retained-control'/h.ROLES[-1]
    assert (oracle/'call-0.state').read_bytes() == canonical
    assert (oracle/'call-0.events').read_bytes() == inputs[prepared+'tick.events']
    admission = d['admission']
    assert admission['status'] == 'checks-passed' and admission['warmup_ticks'] == 1320
    # Independently decode pinned image data, never any retained executable or downloaded helper.
    golden = ROOT/'build/doom-e2e-work/upstream-golden-1320.tga.zst'
    assert sha(golden.read_bytes()) == d['pins']['pvm-doom-assets.json']['files']['test-data/doom_01320.tga.zst']
    tga = subprocess.check_output(['zstd', '-d', '--stdout', str(golden)], timeout=15)
    assert len(tga) < 2*1024**2
    width, height, rgba = tga_rgba(tga)
    assert (width, height) == (640, 400) and sha(rgba) == admission['golden_rgba_sha256']
    for path, wanted in admission['sources'].items():
        assert sha(git(HEAD, path)) == wanted
    for name, wanted in admission['inputs'].items():
        assert sha(inputs[prepared+name]) == wanted
    assert admission['linked_sha256'] == sha(inputs['build/tests/pvm-doom/doom.polkavm'])
    wad = 'vendor/polkavm/examples/doom/roms/doom1.wad'
    assert sha(inputs[wad]) == d['pins']['pvm-doom-assets.json']['files']['examples/doom/roms/doom1.wad']
    for row in admission['builds']:
        assert row['exit_code'] == 0
        retained(row['log'])
    assert len(admission['controls']) == 6
    for row in admission['controls']:
        assert row['passed'] and row['run']['exit_code'] != 0
        retained(row['run']['log'])
    for side in ('native', 'reference'):
        row = d['gas_qualification'][side]
        assert row['exit_code'] == 0
        command(row)
    assert d['gas_qualification']['native']['output'] == d['gas_qualification']['reference']['output']
    prices = h.validate_gas(d['gas_qualification']['native']['output'])
    assert retained(PREFIX+'gas-facts.txt').read_text() == d['gas_qualification']['native']['output']

    history = [row for row in d['controls'] if row['control'] == 'history-and-ordered-hosts']
    assert [row['role'] for row in history] == list(h.ROLES[::-1])
    for row in history:
        assert row['run']['exit_code'] == 0
        command(row['run'])
        measured, observed = h.observe(row['run']['output'], OracleView(oracle, True), row['role'], 8,
            catalog, trace=True, mode='history')
        assert observed == row['observed']
        if row['role'] == h.ROLES[-1]:
            reference = observed
            assert reference['frames'][0]['rgba_sha256'] == admission['golden_rgba_sha256']
        else:
            h.legacy.compare(reference, observed, 8)
        actual = folder/'tests/pvm-doom-e2e/retained-control'/row['role']
        for call in (range(8) if row['role'] == h.ROLES[-1] else (0, 7)):
            for suffix in ('state', 'events', 'hosts'):
                assert (actual/f'call-{call}.{suffix}').read_bytes() == (oracle/f'call-{call}.{suffix}').read_bytes()
    assertions = [row for row in d['controls'] if row['control'] == 'active-assertion']
    assert [row['role'] for row in assertions] == list(h.ROLES)
    for row in assertions:
        assert row['run']['exit_code'] != 0
        command(row['run'])
        needle = 'DOOM e2e reference assertion control' if row['role'] == h.ROLES[-1] else 'DOOM e2e native assertion control'
        assert needle in row['run']['output']
    mismatch = [row for row in d['controls'] if row['control'] == 'source-mismatch']
    assert [row['role'] for row in mismatch] == [h.ROLES[1], h.ROLES[-1]]
    for row in mismatch:
        assert row['run']['exit_code'] != 0
        command(row['run'])
        assert ('InvalidPreparedProgram' if row['role'] != h.ROLES[-1] else 'DOOM e2e source owner mismatch') in row['run']['output']
    assert {row['control'] for row in d['controls'] if row.get('refused')} == {'changed-pixel', 'omitted-frame', 'reordered-frame'}
    assert len(d['controls']) == 13
    for row in d['runs']:
        assert row['run']['exit_code'] == 0
        args = command(row['run'])
        endpoint = 'reference' if row['role'] == h.ROLES[-1] else 'experimental' if row['role'] == h.ROLES[2] else 'production'
        assert len(args) == 1 and args[0].endswith('/'+endpoint+'-0')
        measured, observed = h.observe(row['run']['output'], OracleView(oracle, False), row['role'], row['batch'], catalog)
        assert (measured, observed) == (row['measured'], row['observed'])
        if row['order'] == row['sample'] == 0 and row['batch'] == 8:
            actual = folder/'tests/pvm-doom-e2e/retained-output'/row['role']
            for call in (0, 7):
                for suffix in ('state', 'events'):
                    assert (actual/f'call-{call}.{suffix}').read_bytes() == (oracle/f'call-{call}.{suffix}').read_bytes()
                assert not (actual/f'call-{call}.hosts').exists()
    if complete:
        assert d['summary'] == h.summarize(d['runs'])
    else:
        assert len(d['runs']) < len(h.matrix()) and d['summary'] == []
    for path, wanted in d['identities'].items():
        # Repository-owned inputs remain verifiable independently of CI's self-reported hashes.
        if not path.startswith(('build/', 'vendor/')):
            assert sha(git(HEAD, path)) == wanted
    return dict(status='passed' if complete else 'incomplete-verified-prefix', revision=HEAD, architecture=arch, archive_digest=meta['digest'],
        payloads=payloads, source_files=source_files, retained_ELFs=9, equal_normal_pairs=3,
        native_builds=6, reference_builds=3, static_price_entries=len(prices), controls=13,
        measured_processes=len(d['runs']), measured_calls=sum(row['batch'] for row in d['runs']),
        expected_processes=312, expected_calls=1144, matches_independently_inspected_preflight_images=True,
        performance_summary_accepted=complete, summary=d['summary'],
        limitations='Inert audit only. Full oracle plus bounded first/last actual outputs retained; all other process observations match oracle bytes and CI compares each full raw result. Reference instance/cache freshness is private compatibility-adapter cost. Historical eager differs beyond policy. Untimed audits affect caches. No general JAM gas or arbitrary-exit parity claim.')


if __name__ == '__main__':
    base = Path(sys.argv[1])
    rows = [audit(path) for path in sorted(base.glob('pvm-doom-e2e-*')) if path.is_dir()]
    assert rows
    if len(rows) == 2 and all(row['status'] == 'passed' for row in rows):
        # Only a completed successful exact run and all three mandatory jobs qualify a both-CPU result.
        dispatch = json.loads((base/'run.json').read_text())
        assert dispatch['status'] == 'completed' and dispatch['conclusion'] == 'success'
        jobs = json.loads((base/'jobs.json').read_text())['jobs']
        names = {'Build / Smoke', 'Perf / DOOM Matched E2E (Linux ARM64)', 'Perf / DOOM Matched E2E (Linux x86-64)'}
        selected = [job for job in jobs if job['name'] in names]
        assert {job['name'] for job in selected} == names
        assert all(job['status'] == 'completed' and job['conclusion'] == 'success' for job in selected)
        assert {row['architecture'] for row in rows} == {'arm64', 'x86_64'}
        oracle_roots = [base/f'pvm-doom-e2e-{arch}-1/tests/pvm-doom-e2e/retained-control/reference-untraced'
                        for arch in ('arm64', 'x86_64')]
        for call in range(8):
            for suffix in ('state', 'events', 'hosts'):
                assert (oracle_roots[0]/f'call-{call}.{suffix}').read_bytes() == (oracle_roots[1]/f'call-{call}.{suffix}').read_bytes()
    (base/'author-audit.json').write_text(json.dumps(rows, indent=2)+'\n')
    print(json.dumps([{key:row[key] for key in ('status', 'architecture', 'revision')} for row in rows]))
