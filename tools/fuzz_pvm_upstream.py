#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run pristine pinned upstream campaigns, then replay JAM-adapted VM corpus in checked Nimony.

Make owns provisioning. Outputs, mutable coverage corpora and failure artifacts stay under build/.
The original targets are not Ragnarök parity checks; only the separately reported bridge is.
"""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import shutil
import subprocess
import struct
import sys
import tomllib

from fuzz_pvm_program import campaign_observation, run_group
from native_checks import NativeChecks, ROOT
from setup_nimony import installed

UPSTREAM = ROOT/'vendor/polkavm'
BUILD = ROOT/'build/pvm-upstream-fuzz'
NIGHTLY = 'nightly-2025-03-29'
FLAGS = ('-Cpasses=sancov-module -Cllvm-args=-sanitizer-coverage-level=4 '
         '-Cllvm-args=-sanitizer-coverage-inline-8bit-counters '
         '-Cllvm-args=-sanitizer-coverage-pc-table '
         '-Cllvm-args=-sanitizer-coverage-trace-compares -Cdebug-assertions --cfg fuzzing')
LINUX_ONLY = {'fuzz_shm_allocator', 'fuzz_page_set'}


def digest(path):
    """Hash exact inputs, including lockfiles and the source slice used by the generated adapter."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inventory():
    """Fail source drift or target omissions before a compiler or campaign can report success."""
    pins = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
    commit = subprocess.check_output(['git', '-C', UPSTREAM, 'rev-parse', 'HEAD'], text=True).strip()
    if commit != pins['commit']:
        raise ValueError('PolkaVM checkout differs from its pin')
    dirty = subprocess.check_output(['git', '-C', UPSTREAM, 'status', '--porcelain', '--untracked-files=no'], text=True)
    if dirty:
        raise ValueError('PolkaVM source must remain pristine')
    hashes = {}
    paths = [UPSTREAM/'fuzz/Cargo.toml', UPSTREAM/'fuzz/Cargo.lock', UPSTREAM/'fuzz/rust-toolchain.toml',
             UPSTREAM/'ci/jobs/fuzz.sh', *sorted((UPSTREAM/'fuzz/fuzz_targets').glob('*.rs'))]
    for path in paths:
        relative = str(path.relative_to(UPSTREAM))
        actual = digest(path)
        if pins['source_sha256'].get(relative) != actual:
            raise ValueError('Unpinned or changed upstream fuzz source: '+relative)
        hashes[relative] = actual
    manifest = tomllib.loads((UPSTREAM/'fuzz/Cargo.toml').read_text())
    targets = sorted(item['name'] for item in manifest['bin'])
    ci_targets = sorted(set(re.findall(r'\bfuzz_[a-z_]+\b', (UPSTREAM/'ci/jobs/fuzz.sh').read_text())))
    if targets != ci_targets or len(targets) != len(set(targets)):
        raise ValueError('Upstream manifest/CI target inventory differs')
    if tomllib.loads((UPSTREAM/'fuzz/rust-toolchain.toml').read_text())['toolchain']['channel'] != NIGHTLY:
        raise ValueError('Upstream nightly changed')
    return dict(commit=commit, source_sha256=hashes, targets=targets)


def prepare_reference():
    """Copy unmodified targets/lockfile; relocate dependency paths only in the generated manifest."""
    copied = BUILD/'reference/fuzz'
    shutil.copytree(UPSTREAM/'fuzz', copied, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('target', 'corpus', 'artifacts', 'coverage'))
    manifest = (copied/'Cargo.toml').read_text().replace('"../crates/', '"'+str(UPSTREAM/'crates')+'/')
    manifest += '\n[[bin]]\nname = "ragnarok-jam-bridge"\npath = "bridge.rs"\n'
    (copied/'Cargo.toml').write_text(manifest)
    original = (UPSTREAM/'fuzz/fuzz_targets/fuzz_polkavm.rs').read_text()
    prefix = original[original.index('#[derive(Arbitrary, Debug)]'):original.index('fn build_program_blob(')]
    (copied/'bridge.rs').write_text('use arbitrary::Arbitrary;\nuse polkavm_common::program::{asm, Instruction, Reg};\n'
                                   +prefix+(ROOT/'tests/fuzz/pvm_upstream_bridge.rs.inc').read_text())
    return copied/'Cargo.toml'


def seed_inputs(folder):
    """Deterministic supplemental raw Arbitrary inputs; provenance distinguishes these from mutations."""
    folder.mkdir(parents=True, exist_ok=True)
    generator = random.Random(0x504f4c4b41564d)
    paths = []
    for index in range(256):
        data = generator.randbytes(8+index % 57)
        path = folder/hashlib.sha256(data).hexdigest()
        path.write_bytes(data)
        paths.append(path)
    return paths


def run():
    """Persist incomplete/failing status even if a build, timeout, target or native assertion fails."""
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(schema=1, status='running', upstream=[], bridge={}, commands=[])
    result = BUILD/'results.json'
    summary = BUILD/'summary.md'
    summary.unlink(missing_ok=True)

    def save():
        """Do not let an older successful campaign stand in for this invocation."""
        result.write_text(json.dumps(report, indent=2)+'\n')

    def command(args, name, environment, timeout=900):
        """Retain commands and retire whole process groups on bounded failures/timeouts."""
        row = run_group(args, name, BUILD, environment, timeout)
        report['commands'].append({k: v for k, v in row.items() if k != 'output'})
        save()
        if row['exit_code'] != 0 or row['timed_out']:
            raise ValueError('Failed '+name+'; see '+row['log'])
        return row['output']

    save()
    try:
        report['inventory'] = inventory()
        requested = os.environ.get('FUZZ_RUNS', '10000')
        if re.fullmatch(r'[1-9][0-9]*', requested) is None:
            raise ValueError('FUZZ_RUNS must be a canonical positive integer')
        count = int(requested)
        if not 1000 <= count <= 1000000:
            raise ValueError('FUZZ_RUNS must be 1000..1000000')
        environment = dict(os.environ)
        environment.pop('CORRECTNESS_FUZZER', None)
        environment.pop('RUSTFLAGS', None)
        environment.pop('CARGO_ENCODED_RUSTFLAGS', None)
        environment['ASAN_OPTIONS'] = 'abort_on_error=1:detect_leaks=0'
        host_info = command(['rustup', 'run', NIGHTLY, 'rustc', '-vV'], 'rust-identity', environment)
        host = re.search(r'^host: (.+)$', host_info, re.MULTILINE).group(1)
        # The pinned 2025 ASan runtime deadlocks in dyld initialization on macOS 27.
        # Linux CI always requires ASan; local macOS coverage-only runs make no sanitizer claim.
        sanitizer = 'address' if platform.system() == 'Linux' else 'none'
        report.update(host=host, nightly=NIGHTLY, sanitizer=sanitizer, requested_runs=count)
        manifest = prepare_reference()
        instrumented = dict(environment, RUSTFLAGS=FLAGS+(' -Zsanitizer=address' if sanitizer == 'address' else ''))
        report['rustflags'] = instrumented['RUSTFLAGS']
        supported = [name for name in report['inventory']['targets']
                     if platform.system() == 'Linux' and platform.machine() in ('x86_64', 'amd64')
                     or name not in LINUX_ONLY]
        if os.environ.get('CI') and len(supported) != len(report['inventory']['targets']):
            raise ValueError('CI requires the complete Linux x86_64 upstream inventory')
        target_dir = BUILD/('original-'+sanitizer)
        command(['rustup', 'run', NIGHTLY, 'cargo', 'build', '--release', '--locked',
                 '--manifest-path', manifest, '--target', host, '--target-dir', target_dir,
                 *[part for name in supported for part in ('--bin', name)]], 'upstream-build', instrumented)
        seeds = seed_inputs(BUILD/'seeds')
        for name in report['inventory']['targets']:
            if name not in supported:
                report['upstream'].append(dict(target=name, status='unsupported-platform', requirement='Linux x86_64 upstream testing exports'))
                continue
            corpus = BUILD/'corpus'/name
            corpus.mkdir(parents=True, exist_ok=True)
            if name == 'fuzz_polkavm':
                for seed in seeds:
                    shutil.copy2(seed, corpus/seed.name)
            if name == 'fuzz_program_blob':
                # Arbitrary requires all nine u32 fields plus a bool; an empty corpus never reaches them in a short smoke run.
                for bounded in (False, True):
                    data = struct.pack('<9I?', 0, 0, 0, 0, 4096, 1, 1, 8192, 32, bounded)
                    (corpus/hashlib.sha256(data).hexdigest()).write_bytes(data)
            artifacts = BUILD/'artifacts'/name
            artifacts.mkdir(parents=True, exist_ok=True)
            output = command([target_dir/host/'release'/name, corpus, f'-runs={count}', '-seed=1',
                              '-max_len=4096', '-timeout=20', '-rss_limit_mb=4096', '-max_total_time=600',
                              '-artifact_prefix='+str(artifacts)+'/'], name, environment, timeout=660)
            observed = campaign_observation(output, count)
            report['upstream'].append(dict(target=name, status='passed', **observed))
            save()
            print(name+': '+str(observed), flush=True)
        # The adapter uses only public APIs and original generator bytes, with a separate non-fuzz build.
        command(['rustup', 'run', NIGHTLY, 'cargo', 'build', '--release', '--locked',
                 '--manifest-path', manifest, '--target-dir', BUILD/'bridge-target', '--bin', 'ragnarok-jam-bridge'],
                'bridge-build', environment)
        inputs = BUILD/'bridge-inputs'
        if inputs.exists():
            shutil.rmtree(inputs)
        inputs.mkdir(parents=True)
        provenance = {}
        for origin, paths in [('supplemental-seed', seeds), ('upstream-vm-corpus', sorted((BUILD/'corpus/fuzz_polkavm').iterdir()))]:
            for path in paths:
                data = path.read_bytes()
                identity = hashlib.sha256(data).hexdigest()
                (inputs/identity).write_bytes(data)
                provenance.setdefault(identity, []).append(dict(origin=origin, path=str(path.relative_to(ROOT))))
        frames = BUILD/'frames'
        # The adapter outputs complete frames only; stale frames cannot enter this invocation.
        if frames.exists():
            shutil.rmtree(frames)
        output = command([BUILD/'bridge-target/release/ragnarok-jam-bridge', inputs, frames], 'bridge', environment, timeout=180)
        rows = [line.split('\t') for line in output.splitlines()]
        if len(rows) != len(provenance) or {row[0] for row in rows} != set(provenance):
            raise ValueError('Incomplete bridge accounting')
        statuses = collections.Counter(row[1] for row in rows)
        allowed = {'bridged', 'skipped-arbitrary', 'skipped-operation-limit', 'skipped-non-jam-opcode'}
        if set(statuses)-allowed or statuses['bridged'] == 0:
            raise ValueError('No valid bridge cases or unrecognized refusal')
        bridged = [row for row in rows if row[1] == 'bridged']
        seed_identities = {digest(path) for path in seeds}
        mutant_names = {row[0] for row in bridged if row[0] not in seed_identities}
        if not mutant_names:
            raise ValueError('No actual upstream VM mutations reached the bridge')
        opcodes = sorted({int(op) for row in bridged for op in row[4].split(',')})
        nontrivial = sum(int(row[2]) > 2 and row[4].split(',')[1] not in ('0', '1') for row in bridged)
        if nontrivial < 8 or len(opcodes) < 8:
            raise ValueError('Trivial bridge coverage cannot pass')
        report['bridge'] = dict(status='running', profile='JamV1 Sync Full L2Hit', backend='interpreter', gas=512,
                                input_provenance=provenance, accounting=dict(statuses),
                                nontrivial_programs=nontrivial, upstream_mutated_programs=len(mutant_names), serialized_opcodes=opcodes,
                                reference_source_sha256=digest(ROOT/'tests/fuzz/pvm_upstream_bridge.rs.inc'))
        compiler, _ = installed()
        report['native'] = dict(compiler=str(compiler), compiler_sha256=digest(compiler),
                                source_sha256={str(p.relative_to(ROOT)): digest(p) for p in
                                [ROOT/'tests/fuzz/pvm_upstream_target.nim', ROOT/'tests/fuzz/pvm_upstream_replay.nim']})
        checks = NativeChecks(BUILD, lto=False)
        build_row, replay = checks.build(compiler, ROOT/'tests/fuzz/pvm_upstream_replay.nim', 'replay')
        report['commands'].append({k: v for k, v in build_row.items() if k != 'output'})
        if build_row['exit_code'] != 0:
            raise ValueError('Native replay build failed')
        cases = sorted(frames.glob('*.bin'))
        if len(cases) != 2*statuses['bridged']:
            raise ValueError('Missing bridge frames')
        # One file per process makes a fatal assertion unambiguously identify its original input/profile.
        for case in cases:
            row = run_group([replay, case], 'replay-last', BUILD, environment, 20)
            if row['exit_code'] != 0 or row['timed_out']:
                failure = BUILD/'artifacts/bridge'
                failure.mkdir(parents=True, exist_ok=True)
                shutil.copy2(case, failure/case.name)
                identity = case.stem.rsplit('-', 1)[0]
                shutil.copy2(inputs/identity, failure/(identity+'.raw'))
                report['bridge'].update(status='failed', failing_frame=case.name, replay=row)
                raise ValueError('Native differential mismatch: '+case.name)
        # Prove assertions remain active through this exact checked replay executable.
        control = bytearray(cases[0].read_bytes())
        control[145] ^= 1
        control_path = BUILD/'wrong-register.bin'
        control_path.write_bytes(control)
        row = run_group([replay, control_path], 'assertion-control', BUILD, environment, 20)
        if row['exit_code'] == 0 or row['timed_out'] or 'upstream register mismatch' not in row['output']:
            raise ValueError('Differential assertion control failed')
        report['bridge'].update(status='passed', frames=len(cases), assertion_control='passed',
                                frame_sha256={case.name: digest(case) for case in cases})
        inventory()  # No generated files may have modified the reference checkout.
        report['status'] = 'passed' if len(supported) == len(report['inventory']['targets']) else 'partial-platform'
        text = ('| Check | Result |\n|---|---|\n'+''.join(f'| {r["target"]} | {r["status"]}'+(f' ({r["runs"]:,} runs)' if 'runs' in r else '')+' |\n' for r in report['upstream'])
                +f'| JAM → Ragnarök | {len(cases)} frames; {nontrivial} nontrivial programs; {len(opcodes)} serialized opcodes |\n'
                +f'\nBackend: interpreted. Upstream nightly: {NIGHTLY}. Sanitizer: {sanitizer}.\n'
                +f'\nBridge accounting: `{dict(statuses)}`. Local status: **{report["status"]}**.\n')
        summary.write_text(text)
        print(text)
    except Exception as error:
        report.update(status='failed', error=str(error))
        print(str(error), file=sys.stderr)
        return 1
    finally:
        save()
    return 0


def replay_raw(path, minimize=False):
    """Replay original Arbitrary bytes, optionally deleting chunks while retaining the same profile/assertion."""
    inventory()
    if not Path(path).is_file() or Path(path).stat().st_size > 4096:
        raise ValueError('Original input must be a bounded regular file')
    with Path(path).open('rb') as source:
        data = source.read(4097)
    if not 1 <= len(data) <= 4096:
        raise ValueError('Original input must contain 1..4096 bytes')
    folder = BUILD/'reproduction'
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    environment = dict(os.environ)
    for name in ('CORRECTNESS_FUZZER', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS'):
        environment.pop(name, None)
    attempt = 0

    def observe(raw):
        """Only matching native semantic assertions qualify; build/reference/local-limit failures stop reduction."""
        nonlocal attempt
        attempt += 1
        case_folder = folder/str(attempt)
        inputs = case_folder/'inputs'
        frames = case_folder/'frames'
        inputs.mkdir(parents=True)
        (inputs/hashlib.sha256(raw).hexdigest()).write_bytes(raw)
        row = run_group([BUILD/'bridge-target/release/ragnarok-jam-bridge', inputs, frames],
                        'reference', case_folder, environment, 20)
        if row['exit_code'] != 0 or row['timed_out']:
            raise ValueError('Reference replay failed; inspect '+row['log'])
        if '\tbridged\t' not in row['output']:
            return None
        for frame in sorted(frames.glob('*.bin')):
            result = run_group([BUILD/'replay', frame], 'native-'+frame.stem[-1], case_folder, environment, 20)
            if result['timed_out']:
                raise ValueError('Local replay timeout; not a guest exit')
            if result['exit_code'] != 0:
                signature = re.search(r'upstream (?:exit|gas|PC|fault|register|memory) mismatch', result['output'])
                if signature is None:
                    raise ValueError('Nonsemantic native failure; inspect '+result['log'])
                return frame.stem[-1], signature.group(), frame
        return None

    original = observe(data)
    if original is None:
        print('Original input produced no native differential mismatch')
        return 0
    best = original
    if minimize:
        # At most 64 candidates bound reduction separately from the fuzz campaign's own run budget.
        chunk = max(1, len(data)//2)
        while chunk and attempt < 65:
            changed = False
            for start in range(0, len(data), chunk):
                candidate = data[:start]+data[start+chunk:]
                if not candidate or attempt >= 65:
                    continue
                observed = observe(candidate)
                if observed is not None and observed[:2] == original[:2]:
                    data, best, changed = candidate, observed, True
                    break
            if not changed:
                chunk //= 2
    (folder/'retained.raw').write_bytes(data)
    shutil.copy2(best[2], folder/'retained.bin')
    (folder/'result.json').write_text(json.dumps(dict(profile=best[0], assertion=best[1],
        attempts=attempt, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()), indent=2)+'\n')
    print(f'Retained {len(data)} bytes, profile {best[0]}, {best[1]}; see {folder}')
    return 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay-raw', type=Path)
    parser.add_argument('--minimize', action='store_true')
    args = parser.parse_args()
    if args.minimize and args.replay_raw is None:
        parser.error('--minimize requires --replay-raw')
    sys.exit(replay_raw(args.replay_raw, args.minimize) if args.replay_raw else run())
