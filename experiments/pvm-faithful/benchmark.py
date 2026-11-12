#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Run the standalone control against the unchanged current interpreted PolkaVM drivers.

Check mode validates all 22 complete workloads without publishing durations. Measure mode
requires native Linux Actions, source-bound slice checks and SIMD evidence, then retains both
process orders and independent reference/reference controls. Production execution is never built.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
from pvm_ci_performance import PerformanceRunner, execution_environment, command_record
from pvm_benchmark_report import NAMES
from pvm_native_ci import host_identity
from setup_nimony import host_pins, verify_identity, verify_version, installed

SCOPE = 'PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu'
BASE = 'c8e384caddce9826e58be45b0084ba7e2d5adf5b'


def digest(path):
    """Identify exact bytes, never timestamps or mutable branch labels."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def candidate_records(output, family, label, role, correctness=False):
    """Consume one complete process with exact scope, alias identity, order and cache continuity."""
    assert role in ('interpreted', 'jit') and family in ('synthetic', 'guest', 'doom')
    lines = output.splitlines()
    assert output.endswith('\n') and lines[:2] == [SCOPE, f'FAITHFUL_ENGINE,1,{role},interpreter,0']
    labels = [f'synthetic-{index}' for index in range(11)] if family == 'synthetic' else [label]
    names = list(NAMES) if family == 'synthetic' else [label]
    assert len(lines) == 3 + len(labels)*13
    result = {}
    cursor = 2
    for expected, name in zip(labels, names):
        # Every cold and reused call must be present; no successful subset may enter a ratio.
        samples, prior = [], 0
        for sample in range(13):
            fields = lines[cursor].split(',')
            cursor += 1
            kind = 'FAITHFUL_VALIDATED' if correctness else 'FAITHFUL_SAMPLE'
            assert len(fields) == (5 if correctness else 7)
            assert fields[:4] == [kind, '1', expected, str(sample)]
            assert all(re.fullmatch(r'0|[1-9][0-9]{0,18}', field) for field in fields[4:])
            values = list(map(int, fields[4:]))
            assert all(0 < value < 2**63 for value in values)
            cache = values[-1]
            assert cache >= prior and cache % 24 == 0
            prior = cache
            row = dict(sample=sample, cache_bytes=cache)
            if not correctness:
                row.update(cpu_ns=values[0], wall_ns=values[1])
            samples.append(row)
        result[name] = dict(invocation=dict(samples=samples), actual='interpreter', requested=role)
    assert lines[cursor:] == [f'FAITHFUL_OK,1,{family}']
    return result


def paired_summary(left, right):
    """Compare the same complete cohort, preserving cold and ten post-warmup reused observations."""
    assert set(left) == set(right) and left
    result = {}
    for name in left:
        # Reject missing/foreign samples before computing either duration ratio.
        assert 'invocation' in left[name] and 'invocation' in right[name]
        a, b = left[name]['invocation']['samples'], right[name]['invocation']['samples']
        assert len(a) == len(b) == 13
        assert [row['sample'] for row in a] == [row['sample'] for row in b] == list(range(13))
        for row in [*a, *b]:
            assert all(type(row[key]) is int and 0 < row[key] < 2**63 for key in ('cpu_ns', 'wall_ns'))
        result[name] = {}
        for clock in ('cpu_ns', 'wall_ns'):
            result[name][clock] = dict(cold=a[0][clock]/b[0][clock],
                reused=statistics.median(row[clock] for row in a[3:]) /
                       statistics.median(row[clock] for row in b[3:]))
    return result


class FreshRunner(PerformanceRunner):
    """Reuse only canonical inputs, pristine Rust controls and parsers from the maintained harness."""

    def __init__(self, compiler, mode, asan=False):
        """Keep experiment receipts distinct from production performance schemas and destinations."""
        super().__init__(ROOT / 'build/pvm-faithful' / ('workloads-asan' if asan else 'workloads'))
        self.compiler = Path(compiler).resolve(strict=True)
        self.mode, self.asan = mode, asan
        self.rust = json.loads((ROOT / 'spec/bandersnatch-pins.json').read_text())['rust']
        self.report.update(schema='faithful-control-v1', performance_qualified=False,
                           mode=mode, asan=asan, jit='interpreter-alias', pairs=[], reference_controls=[])

    def qualify(self):
        """Verify installed pins and exact slice-tested implementation before compiling the embedding."""
        pins = json.loads((ROOT / 'spec/toolchain.json').read_text())
        verify_identity(self.compiler.parent.parent, host_pins(pins))
        verify_version(self.compiler, pins['version'])
        selected, _ = installed(self.compiler.parents[3])
        assert selected.resolve() == self.compiler
        host = host_identity()
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        self.report.update(revision=revision, architecture=host['architecture'], baseline=BASE)
        self.report['identity'].update(host=host, compiler_sha256=digest(self.compiler), rust=self.rust)
        receipt_path = ROOT / 'build/pvm-faithful/slice-checks.json'
        receipt = json.loads(receipt_path.read_text())
        assert receipt['status'] == 'completed-slices-passed'
        assert receipt['compiler_sha256'] == digest(self.compiler)
        for path, expected in receipt['sources'].items():
            # Pure orchestration changes do not invalidate already-tested interpreter code.
            if path.endswith(('.nim', '.h', '.rs', 'Cargo.toml', 'Cargo.lock')):
                assert digest(ROOT / path) == expected, 'stale slice check: ' + path
        self.report['identity']['slice_checks'] = dict(path=str(receipt_path.relative_to(ROOT)), sha256=digest(receipt_path))
        self.seal([self.compiler, receipt_path, *[path for path in HERE.rglob('*')
                   if path.is_file() and '__pycache__' not in path.parts]])
        if self.mode == 'measure':
            # Local correctness, emulated CPUs and sanitizer timings cannot supply accepted ratios.
            assert not self.asan and host['system'] == 'Linux'
            assert os.environ.get('GITHUB_ACTIONS') == 'true'
            assert os.environ.get('GITHUB_SHA') == revision
            assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()
            if host['architecture'] == 'x86_64':
                assert re.search(r'\bavx2\b', Path('/proc/cpuinfo').read_text())
        self.report['identity']['clang'] = self.command(['clang', '--version'], 'clang-version')['output']
        self.report['identity']['rustc'] = self.command(['rustup', 'run', self.rust, 'rustc', '--version', '--verbose'], 'rust-version')['output']
        overrides = {key: os.environ[key] for key in ('RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS') if os.environ.get(key)}
        self.report['identity']['build_overrides'] = overrides
        assert not overrides, 'undeclared compiler flags invalidate the control'

    def build_images(self):
        """Compile only the new engine; record per-unit features without modifying the compiler."""
        wrapper = self.folder / 'cc'
        wrapper.mkdir(exist_ok=True)
        (wrapper / 'clang').write_bytes((HERE / 'clang_wrapper.py').read_bytes())
        (wrapper / 'clang').chmod(0o755)
        real = str(Path(shutil.which('clang')).resolve(strict=True))
        log = self.folder / 'clang-commands.jsonl'
        log.write_text('')
        env = execution_environment(FAITHFUL_REAL_CLANG=real, FAITHFUL_CLANG_LOG=str(log))
        env['PATH'] = str(wrapper) + os.pathsep + os.environ['PATH']
        flags = ['--mm:arc', '--cc:clang', '--boundchecks:on', '-d:release', '--opt:speed',
                 '--passC:-flto=thin', '--passL:-flto=thin', '--passC:-I'+str(HERE),
                 '--passC:-I'+str(ROOT / 'tests/performance')]
        if platform.system() == 'Linux':
            flags += ['--passL:-fuse-ld=lld']
        if self.asan:
            flags += ['--passC:-fsanitize=address', '--passL:-fsanitize=address']
        for family in ('synthetic', 'guest', 'doom'):
            # Force rebuilding makes recorded unit feature choices complete and auditable.
            image = self.folder / ('benchmark-'+family)
            row = self.command([self.compiler, 'c', '-f', *flags,
                '--nimcache:'+str(self.folder / ('cache-'+family)), '--out:'+str(image),
                HERE / ('benchmark_'+family+'.nim')], 'build-'+family, env)
            self.report['builds'].append(command_record(row))
            self.images[family] = image
            self.seal([image])
        rows = [json.loads(line) for line in log.read_text().splitlines()]
        selected = [row for row in rows if row['simulator']]
        assert len(selected) == 3, 'simulator unit selection missing or too broad'
        x86 = self.report['architecture'] == 'x86_64'
        assert all(row['avx2'] == (bool(row['simulator']) and x86) for row in rows)
        self.report['identity']['unit_features'] = dict(path=str(log.relative_to(ROOT)), sha256=digest(log))
        if not self.asan:
            # Sanitizer instrumentation can inhibit vectorization; its clocks are never qualified.
            self.codegen()
        self.reference_layout()

    def codegen(self):
        """Retain actual simulator assembly and require packed arithmetic in its tick loop."""
        image = self.images['doom']
        if platform.system() == 'Darwin':
            command = ['xcrun', 'llvm-objdump', '-d', '--no-show-raw-insn', image]
        else:
            command = ['objdump', '-d', '--no-show-raw-insn', image]
        row = self.command(command, 'assembly')
        chunks = re.split(r'(?m)^(?=[0-9a-f]+ <)', row['output'])
        ticks = [chunk for chunk in chunks if re.search(r'^\s*[0-9a-f]+ <_?tickLoop[^>]*>:', chunk)]
        assert ticks, 'missing simulator tick assembly'
        body = '\n'.join(ticks)
        x86 = self.report['architecture'] == 'x86_64'
        patterns = [r'\bvpmovmskb\b', r'\bvp(addb|subb|subsb)\b', r'\bvpcmpeq[bwd]\b'] if x86 else [
            r'\bcmeq(?:\.\w+)?\s+v', r'\b(?:add|sub|sqsub)(?:\.\w+)?\s+v']
        assert all(re.search(pattern, body) for pattern in patterns), 'simulator packed operations missing'
        proof = self.folder / 'simulator-assembly.txt'
        proof.write_text(body)
        self.report['identity']['simd'] = dict(architecture=self.report['architecture'],
            path=str(proof.relative_to(ROOT)), sha256=digest(proof), required_patterns=patterns)

    def reference_layout(self):
        """Verify the actual pinned Rust node layout on this architecture, using release DWARF."""
        binary = self.references['doom']
        if platform.system() == 'Darwin':
            debug = self.folder / 'reference.dSYM'
            self.command(['xcrun', 'dsymutil', binary, '-o', debug], 'reference-dsym')
            tool = ['xcrun', 'llvm-dwarfdump']
        else:
            debug = binary
            tool = [shutil.which('llvm-dwarfdump') or 'llvm-dwarfdump']
        layouts = {}
        for name, expected_size, expected_members in (
            ('LeafNode<u32, polkavm::interpreter::Page>', 320,
             dict(parent=0, vals=8, keys=272, parent_idx=316, len=318)),
            ('InternalNode<u32, polkavm::interpreter::Page>', 416, dict(data=0, edges=320))):
            row = self.command([*tool, '--name='+name, '--show-children', '--recurse-depth=1', debug],
                               'reference-layout-'+name.split('<')[0])
            text = row['output']
            size = re.search(r'DW_AT_byte_size\s+\((0x[0-9a-f]+|[0-9]+)\)', text)
            assert size and int(size[1], 0) == expected_size, 'reference node size changed'
            members = {}
            for member in text.split('DW_TAG_member')[1:]:
                field = re.search(r'DW_AT_name\s+\("([^"]+)"\)', member)
                offset = re.search(r'DW_AT_data_member_location\s+\((0x[0-9a-f]+|[0-9]+)\)', member)
                if field and offset:
                    members[field[1]] = int(offset[1], 0)
            assert members == expected_members, 'reference node field order changed'
            layouts[name] = dict(size=expected_size, members=members, run=command_record(row))
        self.report['identity']['page_map_layout'] = layouts

    def invocation(self, case, role):
        """Use canonical reference arguments and an explicit fresh-interpreter embedding for both roles."""
        args, env, controlled = super().invocation(case, role)
        env = {key: value for key, value in env.items() if not key.startswith('RAGNAROK_FAITHFUL_')}
        if role != 'reference':
            if self.mode == 'check':
                env['RAGNAROK_FAITHFUL_CORRECTNESS_ONLY'] = '1'
            if case['family'] == 'guest':
                name = case['case']
                family = 'pvm-sieve' if name == 'sieve' else 'pvm-pinky' if name == 'pinky' else 'pvm-guests'
                env['RAGNAROK_PVM_SIEVE_ARTIFACT'] = str(ROOT / 'tests/fixtures' / family / (name+'.polkavm'))
            if case['family'] == 'doom':
                env['RAGNAROK_PVM_DOOM_ARTIFACT'] = str(self.doom_blob)
        return args, env, controlled

    def parse(self, output, case, role):
        """Never pass fresh output off as production policy, JIT or reference-lifetime evidence."""
        if role == 'reference':
            return super().parse(output, case, role)
        return candidate_records(output, case['family'], case['case_id'], role, self.mode == 'check')

    def fresh_controls(self, case, role):
        """Exercise live optimized assertions plus altered complete-state/event fixtures."""
        args, env, controlled = self.invocation(case, role)
        family = case['family']
        prefix = case['case_id']+'-'+role
        keys = dict(synthetic='RAGNAROK_PVM_BENCH_ASSERT_PROBE', guest='RAGNAROK_PVM_SIEVE_ASSERT_PROBE', doom='RAGNAROK_PVM_DOOM_ASSERT')
        diagnostics = dict(synthetic='pvm synthetic terminal register mismatch', guest='sieve terminal state mismatch', doom='DOOM terminal state mismatch')
        for kind in (('assertions', 'state', 'events') if family == 'doom' else ('assertions', 'state')):
            probe = dict(env)
            directory = self.folder / 'negative' / prefix / kind
            directory.mkdir(parents=True, exist_ok=True)
            expected = 'assertion control' if kind == 'assertions' else 'DOOM event mismatch' if kind == 'events' else diagnostics[family]
            if kind == 'assertions':
                probe[keys[family]] = '1'
            elif family == 'synthetic':
                changed = bytearray(self.synthetic_fixture.read_bytes())
                changed[12+169] ^= 1
                target = directory / 'fixture.bin'
                target.write_bytes(changed)
                probe['RAGNAROK_PVM_BENCHMARK'] = str(target)
            else:
                origin = self.doom_folder if family == 'doom' else controlled.parent
                for path in origin.iterdir():
                    if path.is_file():
                        shutil.copy2(path, directory / path.name)
                target = directory / (case['case']+'.events' if kind == 'events' else controlled.name)
                changed = bytearray(target.read_bytes())
                changed[8] ^= 1
                target.write_bytes(changed)
                if family == 'doom':
                    probe['RAGNAROK_PVM_DOOM_INPUT'] = str(directory)
                else:
                    probe['RAGNAROK_PVM_SIEVE_EXPECTED'] = str(target)
            try:
                row = self.command(args, prefix+'-refuse-'+kind, probe, expected_failure=True)
                assert row['exit_code'] != 0 and 'Assertion Failure' in row['output'] and expected in row['output']
                self.report['controls'].append(dict(case=case['case_id'], role=role, kind=kind, run=command_record(row)))
            finally:
                # Preserve diagnostic logs, not copies of multi-megabyte private snapshots.
                shutil.rmtree(directory)

    def execute(self):
        """Finish every gate before writing a complete diagnostic report or qualified matrix."""
        self.folder.mkdir(parents=True, exist_ok=True)
        (self.folder / 'summary.md').write_text('Incomplete fresh control; no accepted timing ratios.\n')
        self.checkpoint()
        try:
            self.qualify()
            self.prepare_micro()
            self.prepare_doom()
            self.build_images()
            processes = [self.cases[0], *[case for case in self.cases if case['family'] != 'synthetic']]
            assert len(self.cases) == 22 and len(processes) == 12
            for case in processes:
                # The positive witness precedes negative controls, and every role uses a fresh process.
                for role in ('interpreted', 'jit'):
                    args, env, _ = self.invocation(case, role)
                    row = self.command(args, case['case_id']+'-'+role+'-positive', env)
                    parsed = self.parse(row['output'], case, role)
                    self.report['runs'].append(dict(case=case['case_id'], role=role, run=command_record(row), parsed=parsed))
                    self.fresh_controls(case, role)
                if self.mode == 'measure':
                    super().controls(case, 'reference')
                self.checkpoint()
                print('Validated '+case['case_id']+' (both interpreter roles)', flush=True)
            if self.mode == 'measure':
                self.measure(processes)
            self.verify()
            self.report.update(status='passed', performance_qualified=self.mode == 'measure')
            self.report['sealed_sha256'] = {str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path): value for path, value in self.seals.items()}
            self.checkpoint()
            self.render()
        except Exception as error:
            # Any failure leaves a visibly incomplete report and no stale successful summary.
            self.report.update(status='failed', performance_qualified=False, error=str(error))
            self.checkpoint()
            raise

    def measure(self, processes):
        """Retain independent reference/reference processes and both candidate/reference process orders."""
        for case in processes:
            reference_pair = []
            for side in ('left', 'right'):
                args, env, _ = self.invocation(case, 'reference')
                row = self.command(args, case['case_id']+'-reference-control-'+side, env)
                reference_pair.append(self.parse(row['output'], case, 'reference'))
                self.report['reference_controls'].append(dict(case=case['case_id'], side=side, run=command_record(row), parsed=reference_pair[-1]))
            self.report['reference_controls'].append(dict(case=case['case_id'], ratios=paired_summary(*reference_pair)))
            for role in ('interpreted', 'jit'):
                for index, order in enumerate(((role, 'reference'), ('reference', role))):
                    parsed, commands = {}, {}
                    for endpoint in order:
                        args, env, _ = self.invocation(case, endpoint)
                        row = self.command(args, f'{case["case_id"]}-{role}-order{index}-{endpoint}', env)
                        parsed[endpoint] = self.parse(row['output'], case, endpoint)
                        commands[endpoint] = command_record(row)
                    self.report['pairs'].append(dict(case=case['case_id'], role=role, order=list(order),
                        parsed=parsed, commands=commands, ratios=paired_summary(parsed[role], parsed['reference'])))
            self.checkpoint()
            print('Measured '+case['case_id']+' in both process orders', flush=True)

    def render(self):
        """Publish explicit scope and per-order ratios; never blend these with saved master timings."""
        lines = ['Fresh faithful-style interpreter control', '',
                 'All 22 workloads passed full-state and refusal controls in both interpreter roles.',
                 'JIT is an explicit interpreter alias.']
        if self.mode == 'check':
            lines += ['', 'Local correctness only. No performance ratios qualified.']
        else:
            lines += ['', 'Candidate / unchanged interpreted PolkaVM; values above 1 are slower.',
                      'Reused = median of samples 3–12; cold = sample 0. Raw CPU and wall samples remain in results.json.', '',
                      '| Workload | Role | Process order | Cold CPU | Reused CPU |', '| --- | --- | --- | ---: | ---: |']
            for pair in self.report['pairs']:
                for name, clocks in pair['ratios'].items():
                    values = clocks['cpu_ns']
                    lines.append(f'| {name} | {pair["role"]} | {" then ".join(pair["order"])} | {values["cold"]:.3f}x | {values["reused"]:.3f}x |')
        (self.folder / 'summary.md').write_text('\n'.join(lines)+'\n')


def main():
    """Make supplies pinned setup; command selection is explicit and local defaults never time."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--mode', choices=('check', 'measure'), default='check')
    parser.add_argument('--asan', action='store_true')
    args = parser.parse_args()
    FreshRunner(args.compiler, args.mode, args.asan).execute()


if __name__ == '__main__':
    main()
