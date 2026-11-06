#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Run the current public PVM performance matrix on its qualified native Linux CI host.

One production image per workload family selects interpreted/JIT ownership at runtime. Pinned
interpreted reference fixtures, full-state/refusal controls and unchanged byte identities precede
both process orders. Failure cannot publish a partial matrix as a successful performance report.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib

from native_checks import NativeChecks, ROOT
from native_dependencies import require_submodule
from pvm_arm64_jit_applications import parse_run
from pvm_benchmark import CRATE
from pvm_doom_attribution import (CRATE as DOOM_CRATE, TARGET as DOOM_TARGET,
                                  event_hashes, tga_rgba, timing_samples)
from pvm_guest_compare import unchanged
from pvm_guest_inputs import prepare_inputs
from pvm_jit_platform import RESIDENT_PROOF, comparison_defines
from pvm_native_ci import host_identity
from pvm_performance_report import SCHEMA, case_inventory, publish_report
from pvm_performance_synthetic import parse_synthetic
from pvm_invocation_scope import invocation_scope, scope_diagnostics, full_parsed, measurement_identity
from pvm_reference_lifetime import CODE_LIFETIME, reference_instances, invocation_reference_instances
from setup_nimony import installed

BUILD = ROOT/'build/tests/pvm-performance'
ROLES = ('interpreted', 'jit', 'reference')
ORDERS = (ROLES, ROLES[::-1])
DOOM_WARMUP = 1320


def digest(path):
    """Bind files to bytes without trusting mutable timestamps, names or command descriptions."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def execution_environment(**overrides):
    """Discard inherited experiment/backend controls; each invocation declares its own policy."""
    result = {key: value for key, value in os.environ.items()
              if not key.startswith(('RAGNAROK_PVM_', 'PVM_JIT_', 'PVM_INTERPRETER_',
                                     'PVM_COMPARE_'))}
    result.update({key: str(value) for key, value in overrides.items()})
    # The reference always uses its checked interpreted default, with no optional worker protocol.
    result.pop('RAGNAROK_PVM_REFERENCE_BACKEND', None)
    return result


def command_record(row):
    """Keep log/command/exit evidence without duplicating unbounded process output in reports."""
    return {key: value for key, value in row.items() if key != 'output'}


def intended_refusal(row, family, role, kind):
    """Require the intended live assertion, not merely any failed process or unrelated panic."""
    output = row['output']
    if row['exit_code'] == 0 or not any(word in output for word in ('Assertion Failure', 'panicked')):
        return False
    engine = 'reference' if role == 'reference' else 'native'
    if kind == 'assertions':
        name = {'synthetic': 'pvm synthetic', 'guest': 'pvm sieve', 'doom': 'doom'}[family]
        return name+' '+engine+' assertion control' in output
    if family == 'synthetic':
        return 'pvm synthetic terminal register mismatch' in output
    if family == 'doom':
        diagnostic = ('DOOM event mismatch' if kind == 'events' else 'DOOM terminal state mismatch')
        if role != 'reference':
            diagnostic = 'doom event payload mismatch' if kind == 'events' else 'doom terminal gas mismatch'
        return diagnostic in output
    # The gas oracle must name itself; a clock/setup assertion cannot supply a state refusal.
    diagnostic = ('sieve terminal state mismatch' if role == 'reference' else
                  'pvm sieve native terminal gas mismatch')
    return diagnostic in output


def normalize_execution(parsed, doom=False):
    """Retain existing fields while giving every validated sample its explicit canonical index."""
    execution = parsed['execution']
    samples = execution['samples']
    if len(samples) != 13:
        raise ValueError('Incomplete performance sample process')
    for index, sample in enumerate(samples):
        # Older DOOM parsers validate order in the wire grammar but omit the resulting index.
        if sample.get('sample', index) != index:
            raise ValueError('Unordered performance sample')
        sample['sample'] = index
    if not doom and execution.get('preparation'):
        preparation = execution['preparation']
        if isinstance(preparation, list):
            # PREPARED_PROGRAM is [record-kind, CPU, wall, code-bytes, decoded-instructions].
            execution['preparation_wall_ns'] = [int(preparation[0][2])]
    return parsed


def parse_application(output, role, case, limit, event_bytes=0, require_full=False):
    """Bind retained-reference receipts and the canonical constructor wall clock to strict call grammars."""
    output, full = invocation_scope(output, require_full)
    observed = None
    if full:
        output, observed = scope_diagnostics(output, role)
    doom = case in ('init', 'tick')
    instance = None
    if role == 'reference':
        # Validate retained-code evidence before the maintained strict family call parser sees its grammar.
        label = 'doom-'+case if doom else f'{case}-{limit}'
        parser = invocation_reference_instances if full else reference_instances
        output, instances = parser(output, [label])
        instance = instances[label]
    wall = None
    if doom and role != 'reference':
        lines = output.splitlines()
        fields = lines.pop(1).split(',') if len(lines) > 1 else []
        if (len(fields) != 3 or fields[:2] != ['API_PREPARE_WALL', 'prepared']
                or re.fullmatch(r'0|[1-9][0-9]*' if full else r'[1-9][0-9]*', fields[2]) is None
                or int(fields[2]) >= 1 << 63):
            raise ValueError('Missing or invalid DOOM constructor wall clock')
        wall = int(fields[2])
        output = '\n'.join(lines)+'\n'
    if doom and role == 'reference':
        # A retained instance has one final destruction; old per-call fresh-instance lifecycle is inapplicable.
        parsed = dict(execution=dict(samples=timing_samples(output, 'reference', case, event_bytes)),
                      native=None, policy=None)
    else:
        parsed = parse_run(output, 'interpreter' if role == 'interpreted' else role, case, limit,
                           event_bytes, 'matched-owner-policy-v2', allow_zero_constructor=full)
    if instance is not None:
        parsed['execution']['reference_instance'] = instance
    if wall is not None:
        parsed['execution']['preparation_wall_ns'] = [wall]
    parsed = normalize_execution(parsed, doom)
    return full_parsed(parsed, observed, "doom-process" if doom else "guest-process") if full else parsed


class PreparationChecks:
    """Adapt the maintained guest preparer to the runner's sealed, sanitized command boundary."""

    def __init__(self, runner):
        """Borrow only the current runner; this adapter owns no executables or result state."""
        self.runner = runner

    def command(self, arguments, name, environment=None, timeout=180):
        """Only the preparer's explicit guest name survives its inherited environment copy."""
        selected = (environment or {}).get('RAGNAROK_PVM_GUEST')
        env = execution_environment(**({'RAGNAROK_PVM_GUEST': selected} if selected else {}))
        return self.runner.command(arguments, name, env, timeout)


class PerformanceRunner:
    """Own one run's inventory, immutable input seals, process controls and publication boundary."""

    def __init__(self, folder, scope='all', expected_revision=None):
        """Plan the configured matrix without invoking a tool or accepting prior success artifacts."""
        self.folder = Path(folder)
        self.scope = scope
        self.expected_revision = expected_revision
        self.cases = case_inventory(scope)
        self.checks = NativeChecks(self.folder)
        self.seals = {}
        self.images = {}
        self.references = {}
        self.inputs = {}
        self.doom_folder = self.folder/'doom/prepared'
        self.report = dict(schema=SCHEMA, status='incomplete', scope=scope,
                           runs=[], controls=[], builds=[], identity={})

    def checkpoint(self):
        """Atomically persist current evidence without creating a successful timing table."""
        temporary = self.folder/'results.json.tmp'
        temporary.write_text(json.dumps(self.report, indent=2)+'\n')
        temporary.replace(self.folder/'results.json')

    def seal(self, paths):
        """Admit regular checkout-owned files and remember their immutable current bytes."""
        for path in paths:
            # Compiler executables live in the pinned tool cache; sources/fixtures remain in ROOT.
            path = Path(path)
            if path.is_symlink() or not path.is_file():
                raise ValueError('Missing or redirected performance input: '+str(path))
            value = digest(path)
            if path in self.seals and self.seals[path] != value:
                raise ValueError('Performance input changed before resealing: '+str(path))
            self.seals[path] = value

    def verify(self):
        """A changed fixture, source, executable or compiler cannot supply accepted performance data."""
        unchanged(self.seals)

    def command(self, arguments, name, env=None, timeout=900, expected_failure=False):
        """Check sealed identities on both sides of every tool, including failed controls."""
        self.verify()
        selected = execution_environment() if env is None else env
        row = self.checks.command(arguments, name, environment=selected, timeout=timeout)
        row['benchmark_environment'] = {key: value for key, value in selected.items()
                                        if key.startswith('RAGNAROK_PVM_')}
        self.verify()
        if not expected_failure and row['exit_code']:
            raise RuntimeError('PVM performance command failed: '+row['log'])
        return row

    def qualify(self):
        """Require the exact current clean source, production native host and passed prerequisite receipt."""
        if os.environ.get('GITHUB_ACTIONS') != 'true':
            raise RuntimeError('PVM performance sampling requires native CI')
        if (os.environ.get('GITHUB_JOB') != 'pvm-comparison'
                or not os.environ.get('PVM_CI_JOB_NAME', '').strip()):
            raise ValueError('Missing canonical PVM performance CI job identity')
        host = host_identity()
        if host['system'] != 'Linux' or host['architecture'] not in ('arm64', 'x86_64'):
            raise ValueError('PVM performance requires a supported native Linux runner')
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        expected = self.expected_revision or os.environ.get('GITHUB_SHA')
        if (re.fullmatch(r'[0-9a-f]{40}', revision) is None or not expected or expected != revision):
            raise ValueError('Performance source differs from immutable trigger revision')
        if subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'],
                                   cwd=ROOT, text=True).strip():
            raise ValueError('Performance requires the clean trigger checkout')
        compiler, _ = installed()
        receipt_path = ROOT/'build/tests/pvm-native/results.json'
        receipt = json.loads(receipt_path.read_text())
        ci = {key: os.environ.get(key) for key in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
            'GITHUB_EVENT_NAME', 'GITHUB_REF', 'GITHUB_SHA', 'GITHUB_REPOSITORY',
            'GITHUB_JOB', 'PVM_CI_JOB_NAME')}
        defines = comparison_defines(host['system'], host['machine'], self.scope, ci)
        if (receipt.get('status') != 'passed' or receipt.get('revision') != revision
                or receipt.get('host') != host or not defines
                or receipt.get('compiler_sha256') != digest(compiler)
                or receipt.get('policies', {}).get('native_build_defines') != defines):
            raise ValueError('Missing matching passed native PVM qualification')
        if RESIDENT_PROOF in defines:
            rows = [row for row in receipt.get('qualification', [])
                    if row.get('name') == 'checked-read-resident-oracle']
            if (len(rows) != 1 or rows[0].get('defines') != defines
                    or rows[0].get('status') != 'passed'):
                raise ValueError('Missing exact checked-read resident oracle')
        source_seals = {ROOT/path: value for path, value in receipt.get('sources', {}).items()}
        if not source_seals:
            raise ValueError('Native qualification has no source identities')
        unchanged(source_seals)
        self.compiler, self.defines = compiler, defines
        self.report.update(revision=revision, architecture=host['architecture'])
        self.report['identity'].update(host=host, native_qualification=dict(
            path=str(receipt_path.relative_to(ROOT)), sha256=digest(receipt_path), revision=revision),
            compiler=dict(sha256=digest(compiler), identity=(compiler.parent.parent/'NIGHTLY.txt').read_text()),
            ci=ci,
            doom_warmup_ticks=DOOM_WARMUP, native_build_defines=defines, code_lifetime=CODE_LIFETIME,
            measurement=measurement_identity(),
            toolchain=json.loads((ROOT/'spec/toolchain.json').read_text()),
            build_environment={key: os.environ[key] for key in
                ('RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CFLAGS', 'LDFLAGS') if key in os.environ})
        tracked = subprocess.check_output(['git', 'ls-files', '-z', 'src', 'native/pvm_jit',
            'tools', 'tests/performance', 'tests/fixtures', 'tests/pvm_benchmark_reference.py',
            'tests/pvm_gas_reference.py', 'spec', 'Makefile', '.github/workflows/ci.yml'], cwd=ROOT)
        self.seal([ROOT/path.decode() for path in tracked.split(b'\0') if path])
        self.seal([compiler, receipt_path])
        self.report['identity']['clang'] = self.command(['clang', '--version'], 'clang')['output']
        self.rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
        self.report['identity']['rust'] = self.command(['rustup', 'run', self.rust, 'rustc',
            '--version', '--verbose'], 'rust-version')['output']
        self.checkpoint()

    def reference_sources(self, crate, package):
        """Verify pristine pinned Rust source and complete dependency identities before any reference build."""
        pins = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        self.report['identity']['reference_revision'] = pins['commit']
        upstream = require_submodule(pins)
        fields = ('name', 'version', 'source', 'checksum')
        known = {tuple(row.get(key) for key in fields)
                 for row in tomllib.loads((upstream/'Cargo.lock').read_text())['package']}
        for row in tomllib.loads((crate/'Cargo.lock').read_text())['package']:
            # Local wrappers are the only package additions to the pristine pinned dependency graph.
            if row['name'] != package and tuple(row.get(key) for key in fields) not in known:
                raise ValueError('Unpinned performance reference dependency: '+row['name'])
        for name, expected in pins['source_sha256'].items():
            if digest(upstream/name) != expected:
                raise ValueError('Changed pinned reference source: '+name)
        return upstream

    def reference_build(self, crate, target, package):
        """Build one offline interpreted reference only after its source/dependency qualification."""
        upstream = self.reference_sources(crate, package)
        row = self.command(['rustup', 'run', self.rust, 'cargo', 'build', '--release', '--locked',
            '--offline', '--manifest-path', crate/'Cargo.toml', '--target-dir', target],
            package+'-build')
        self.report['builds'].append(dict(family=package, run=command_record(row)))
        return upstream

    def prepare_micro(self):
        """Prepare all maintained guests and independent synthetic expectations, including both extra sieve sizes."""
        sys.path.insert(0, str(ROOT/'tests'))
        from pvm_benchmark_reference import fixtures
        fixture = ROOT/'tests/fixtures/pvm-benchmark.bin'
        wanted, count = fixtures()
        descriptor = json.loads((ROOT/'tests/fixtures/pvm_benchmark.fixture.json').read_text())
        if (fixture.read_bytes() != wanted or count != 11
                or digest(fixture) != descriptor['files'][fixture.name]):
            raise ValueError('Synthetic fixture differs from independent full-state expectations')
        gray = json.loads((ROOT/'spec/pins.json').read_text())['graypaper']
        require_submodule(dict(gray, repository=gray['repository'].removeprefix('https://github.com/')))
        self.reference_sources(CRATE, 'ragnarok-pvm-benchmark')
        prepared = prepare_inputs(PreparationChecks(self), self.folder/'inputs')
        self.references['micro'] = prepared['reference']
        self.report['identity']['guest_provenance'] = prepared['provenance']
        self.report['preparations'] = list(prepared['preparations'])
        self.report['builds'].extend(dict(family='ragnarok-pvm-benchmark', run=row)
                                     for row in prepared['builds'])
        for guest, limit, data, expected in prepared['inputs']:
            self.inputs[f'{guest}-{limit}'] = (data, expected)
        for limit in (10000, 10000000):
            # Generate missing sizes by name, never by a positional index in an evolving cohort.
            destination = self.folder/'inputs/sieve'/str(limit)
            destination.mkdir(parents=True, exist_ok=True)
            row = self.command([prepared['reference'], '--sieve-prepare',
                ROOT/'tests/fixtures/pvm-sieve/sieve.polkavm', destination, limit, 1],
                'prepare-sieve-'+str(limit), execution_environment(RAGNAROK_PVM_GUEST='sieve'))
            if re.fullmatch(r'SIEVE_PREPARED,'+str(limit)+r',[1-9][0-9]*,[1-9][0-9]*\n',
                            row['output']) is None:
                raise ValueError('Missing complete extra-sieve preparation identity')
            self.report['preparations'].append(dict(guest='sieve', limit=limit,
                                                    preparation=command_record(row)))
            self.inputs[f'sieve-{limit}'] = (destination/f'input-{limit}.bin',
                                            destination/f'expected-{limit}.bin')
        self.synthetic_fixture = fixture
        self.seal([*prepared['identities'], prepared['reference'], fixture,
                   *(path for pair in self.inputs.values() for path in pair)])

    def prepare_doom(self):
        """Link pinned DOOM, prepare canonical warmup1320 snapshots, and compare upstream video golden."""
        upstream = self.reference_build(DOOM_CRATE, DOOM_TARGET, 'ragnarok-pvm-doom')
        pins = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        assets = json.loads((ROOT/'spec/pvm-doom-assets.json').read_text())
        if assets['polkavm_commit'] != pins['commit']:
            raise ValueError('DOOM asset/source pin disagreement')
        for name, expected in assets['files'].items():
            # Complete licenses, original source and golden files stay pinned, not candidate-generated.
            if digest(upstream/name) != expected:
                raise ValueError('Changed DOOM asset: '+name)
        reference = DOOM_TARGET/'release/ragnarok-pvm-doom'
        folder = self.folder/'doom'
        folder.mkdir(parents=True, exist_ok=True)
        elf, self.doom_blob = folder/'doom.elf', folder/'doom.polkavm'
        self.rom = upstream/'examples/doom/roms/doom1.wad'
        self.command(['zstd', '-d', '-f', upstream/'test-data/doom_64.elf.zst', '-o', elf],
                     'doom-decompress')
        self.command([reference, 'link', elf, self.doom_blob], 'doom-link')
        self.command([reference, 'prepare', self.doom_blob, self.rom, self.doom_folder, DOOM_WARMUP],
                     'doom-prepare')
        golden = folder/'golden.tga'
        self.command(['zstd', '-d', '-f', upstream/f'test-data/doom_{DOOM_WARMUP:05d}.tga.zst',
                      '-o', golden], 'doom-golden')
        width, height, wanted = tga_rgba(golden.read_bytes())
        if (width, height) != (640, 400):
            raise ValueError('Wrong upstream DOOM golden dimensions')
        outputs = {phase: event_hashes((self.doom_folder/(phase+'.events')).read_bytes())
                   for phase in ('init', 'tick')}
        data, cursor, last = (self.doom_folder/'tick.events').read_bytes(), 0, None
        while cursor < len(data):
            # event_hashes already validated complete bounded framing and video dimensions.
            kind, length = data[cursor], int.from_bytes(data[cursor+1:cursor+5], 'little')
            cursor += 5
            if kind == 1:
                last = data[cursor:cursor+length]
            cursor += length
        if last is None:
            raise ValueError('Missing canonical DOOM video')
        actual = bytearray(last)
        for at in range(0, len(actual), 4):
            # Match the pinned upstream BGR/opaque-alpha normalization before byte equality.
            actual[at], actual[at+2], actual[at+3] = actual[at+2], actual[at], 255
        if actual != wanted:
            raise ValueError('DOOM canonical upstream frame1320 mismatch')
        self.report['identity']['doom'] = dict(warmup_ticks=DOOM_WARMUP, outputs=outputs,
            golden_rgba_sha256=hashlib.sha256(wanted).hexdigest(), assets=assets)
        self.references['doom'] = reference
        self.seal([reference, self.doom_blob, self.rom, golden,
                   *sorted(self.doom_folder.glob('*')),
                   *(upstream/name for name in assets['files'])])

    def build_images(self):
        """Build one current production image per selected family; both runtime policies use those exact bytes."""
        families = {case['family'] for case in self.cases}
        drivers = dict(synthetic='pvm_workload', guest='pvm_sieve', doom='pvm_doom')
        for family in sorted(families):
            # Diagnostic receipt exports are shared, copied only after all clocks and validation.
            defines = self.defines+([] if family == 'synthetic' else ['pvmArm64JitOwnerReceipt'])
            row, binary = self.checks.build(self.compiler,
                ROOT/'tests/performance'/(drivers[family]+'.nim'), 'current-'+family,
                defines=defines, cflags=['-I'+str(ROOT/'tests/performance'),
                    '-I'+str(ROOT/'native/pvm_jit')], environment=execution_environment())
            self.verify()
            if row['exit_code'] or 'Error:' in row['output'] or 'FAILURE' in row['output']:
                raise RuntimeError('Current production PVM image failed: '+row['log'])
            self.images[family] = binary
            self.report['builds'].append(dict(family=family, defines=defines,
                binary=str(binary), binary_sha256=digest(binary), run=command_record(row)))
            self.seal([binary])

    def invocation(self, case, role):
        """Describe one explicit backend invocation without launching it or inheriting experiment knobs."""
        family, name, limit = case['family'], case['case'], case['limit']
        env = execution_environment(RAGNAROK_PVM_BACKEND=role if role != 'reference' else '',
                          RAGNAROK_PVM_PERFORMANCE='1')
        controlled = None
        if family == 'synthetic':
            env.update(RAGNAROK_PVM_BENCHMARK=str(self.synthetic_fixture),
                       RAGNAROK_PVM_PRICING='prepared', RAGNAROK_PVM_BENCH_ASSERT_PROBE='0')
            args = ([self.references['micro'], self.synthetic_fixture, 'interpreter'] if role == 'reference'
                    else [self.images[family]])
            controlled = self.synthetic_fixture
        elif family == 'guest':
            data, controlled = self.inputs[case['case_id']]
            env.update(RAGNAROK_PVM_GUEST=name, RAGNAROK_PVM_PRICING='prepared',
                RAGNAROK_PVM_SIEVE_SAMPLES='13', RAGNAROK_PVM_SIEVE_CLOCK='1',
                RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_SIEVE_INPUT=str(data),
                RAGNAROK_PVM_SIEVE_EXPECTED=str(controlled))
            fixture = ROOT/'tests/fixtures'/('pvm-sieve' if name == 'sieve' else
                'pvm-pinky' if name == 'pinky' else 'pvm-guests')/(name+'.polkavm')
            args = ([self.references['micro'], '--sieve', fixture, data.parent, limit, 13]
                    if role == 'reference' else [self.images[family]])
        else:
            # Full reference and public brackets include restoration and normal output publication.
            controlled = self.doom_folder/(name+'.expected')
            env.update(RAGNAROK_PVM_DOOM_PRICING='prepared', RAGNAROK_PVM_DOOM_PREPARATION='1',
                RAGNAROK_PVM_DOOM_TIMING='1', RAGNAROK_PVM_DOOM_ASSERT='0',
                RAGNAROK_PVM_LOCAL_ONECALL='0', RAGNAROK_PVM_DOOM_INPUT=str(self.doom_folder),
                RAGNAROK_PVM_DOOM_PHASE=name, RAGNAROK_PVM_DOOM_ROM=str(self.rom),
                RAGNAROK_PVM_DOOM_LIFECYCLE='1' if role == 'reference' else '0')
            args = ([self.references['doom'], 'run', self.doom_blob, self.rom, self.doom_folder, name]
                    if role == 'reference' else [self.images[family]])
        return args, env, controlled

    def parse(self, output, case, role):
        """Validate complete process framing before accepting even a single duration or policy cell."""
        if case['family'] == 'synthetic':
            return parse_synthetic(output, role, require_full=True)
        event_bytes = ((self.doom_folder/(case['case']+'.events')).stat().st_size
                       if case['family'] == 'doom' else 0)
        return {case['case_id']: parse_application(output, role, case['case'], case['limit'],
                                                  event_bytes, require_full=True)}

    def controls(self, case, role):
        """A valid full process precedes assertion/state/event refusals using isolated copied expectations."""
        args, env, controlled = self.invocation(case, role)
        identity = 'synthetic' if case['family'] == 'synthetic' else case['case_id']
        prefix = identity+'-'+role
        positive = self.command(args, prefix+'-positive', env)
        self.parse(positive['output'], case, role)
        self.report['controls'].append(dict(case_id=identity, role=role, kind='positive',
                                            run=command_record(positive)))
        for kind in ('assertions', 'state', 'events') if case['family'] == 'doom' else ('assertions', 'state'):
            # Never alter a sealed canonical input; point each negative process at a private copy.
            probe, probe_args = dict(env), list(args)
            directory = None
            if kind == 'assertions':
                key = {'synthetic': 'RAGNAROK_PVM_BENCH_ASSERT_PROBE',
                       'guest': 'RAGNAROK_PVM_SIEVE_ASSERT_PROBE',
                       'doom': 'RAGNAROK_PVM_DOOM_ASSERT'}[case['family']]
                probe[key] = '1'
            else:
                directory = self.folder/'negative'/prefix/kind
                directory.mkdir(parents=True, exist_ok=True)
                if case['family'] == 'synthetic':
                    target = directory/'fixture.bin'
                    original = self.synthetic_fixture.read_bytes()
                    changed = bytearray(original)
                    changed[12+169] ^= 1
                    target.write_bytes(changed)
                    probe['RAGNAROK_PVM_BENCHMARK'] = str(target)
                    if role == 'reference':
                        probe_args[1] = target
                else:
                    origin = self.doom_folder if case['family'] == 'doom' else controlled.parent
                    for path in origin.iterdir():
                        # Expected bytes and invocation inputs are copied together for the Rust CLI grammar.
                        if path.is_file():
                            shutil.copy2(path, directory/path.name)
                    name = case['case']+'.events' if kind == 'events' else controlled.name
                    target = directory/name
                    changed = bytearray(target.read_bytes())
                    changed[8] ^= 1
                    target.write_bytes(changed)
                    if case['family'] == 'doom':
                        probe['RAGNAROK_PVM_DOOM_INPUT'] = str(directory)
                        if role == 'reference':
                            probe_args[4] = directory
                    else:
                        probe['RAGNAROK_PVM_SIEVE_EXPECTED'] = str(target)
                        probe['RAGNAROK_PVM_SIEVE_INPUT'] = str(directory/self.inputs[case['case_id']][0].name)
                        if role == 'reference':
                            probe_args[3] = directory
            try:
                refused = self.command(probe_args, prefix+'-'+kind, probe, expected_failure=True)
            finally:
                # Logs and refusal identities remain; copied full-memory fixtures need not accumulate.
                if directory is not None:
                    shutil.rmtree(directory)
            if not intended_refusal(refused, case['family'], role, kind):
                raise ValueError('Missing intended '+kind+' refusal: '+prefix)
            self.report['controls'].append(dict(case_id=identity, role=role, kind=kind,
                                                run=command_record(refused)))
        self.checkpoint()

    def execute(self):
        """Complete every positive/refusal gate before sampling both role orders and publishing once."""
        self.folder.mkdir(parents=True, exist_ok=True)
        (self.folder/'summary.md').write_text('PVM performance incomplete; no accepted ratios.\n')
        (self.folder/'samples.csv').unlink(missing_ok=True)
        self.checkpoint()
        try:
            self.qualify()
            families = {case['family'] for case in self.cases}
            if families & {'synthetic', 'guest'}:
                self.prepare_micro()
            if 'doom' in families:
                self.prepare_doom()
            self.build_images()
            processes = [case for case in self.cases if case['family'] != 'synthetic']
            synthetics = [case for case in self.cases if case['family'] == 'synthetic']
            if synthetics:
                # One synthetic process validates all eleven records; do not run the same cohort eleven times.
                processes.insert(0, synthetics[0])
            for case in processes:
                for role in ROLES:
                    self.controls(case, role)
            for order, roles in enumerate(ORDERS):
                for case in processes:
                    for role in roles:
                        args, env, _ = self.invocation(case, role)
                        row = self.command(args, f'{case["case_id"]}-{order}-{role}', env)
                        parsed = self.parse(row['output'], case, role)
                        for case_id, values in parsed.items():
                            # The strict report validator independently checks this exact normalized matrix.
                            item = next(item for item in self.cases if item['case_id'] == case_id)
                            self.report['runs'].append(dict(case_id=case_id, case=item['case'],
                                limit=item['limit'], role=role, order=order, parsed=values,
                                run=command_record(row)))
                        self.checkpoint()
            self.verify()
            self.report['identity']['files'] = {str(path): value for path, value in self.seals.items()}
            # Publication validates and renders all raw-derived tables before marking a complete report passed.
            self.report = publish_report(self.report, self.folder)
        except BaseException as error:
            # Interruptions and renderer errors must erase prior success, keeping fresh failure evidence.
            self.report.update(status='failed', error=str(error))
            self.checkpoint()
            (self.folder/'summary.md').write_text('PVM performance failed; no accepted ratios.\n'
                +str(error).replace('\n', ' ')+'\n')
            (self.folder/'samples.csv').unlink(missing_ok=True)
            raise
        return self.report


def main():
    """Make owns provisioning and native qualification; CLI selects exactly one maintained subset."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scope', choices=('all', 'micro', 'doom'), default='all')
    parser.add_argument('--revision', help='Exact immutable trigger SHA; otherwise GITHUB_SHA')
    arguments = parser.parse_args()
    report = PerformanceRunner(BUILD, arguments.scope, arguments.revision).execute()
    print('PVM performance passed: '+report['architecture']+', '+str(len(case_inventory(report['scope'])))
          +' cases; CPU/wall raw samples and ratios in '+str(BUILD/'summary.md'), flush=True)


if __name__ == '__main__':
    main()
