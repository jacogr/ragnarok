# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise the canonical performance orchestration without compilers, guests or timing claims."""
from copy import deepcopy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import pvm_ci_performance as performance
from pvm_performance_fixtures import SYNTHETICS, retained_instance

EXPECTED_CASES = {
    'arithmetic-10000', 'memory-aligned-1000', 'memory-crossing-1000', 'hosts-aligned-1000',
    'hosts-crossing-1000', 'arithmetic-1', 'arithmetic-16', 'bits-mixed-1000',
    'sparse-aligned-1000', 'sparse-crossing-1000', 'blocks-alternating-1000',
    'sieve-1000', 'sieve-10000', 'sieve-100000', 'sieve-10000000',
    'minimal-1000', 'minimal-100000', 'memset-1000', 'memset-100000', 'pinky-1',
    'doom-init', 'doom-tick',
}


class InertChecks:
    """Emulate observable tool outcomes and copied-fixture refusals, never execute a program."""

    def __init__(self, runner):
        """Keep a bounded command trace and configurable failures for the current test run."""
        self.runner = runner
        self.trace = []
        self.accept_bad_state = False
        self.unrelated_crash = False
        self.tamper = False

    def command(self, arguments, name, environment=None, timeout=180):
        """Return positive records or the expected refusal according to actual copied input bytes."""
        args = [str(value) for value in arguments]
        self.trace.append((name, args, deepcopy(environment)))
        failure = any(environment.get(key) == '1' for key in (
            'RAGNAROK_PVM_BENCH_ASSERT_PROBE', 'RAGNAROK_PVM_SIEVE_ASSERT_PROBE',
            'RAGNAROK_PVM_DOOM_ASSERT'))
        if '-state' in name or '-events' in name:
            # The runner must redirect the real command grammar to a changed copy, not mutate a seal.
            paths = [Path(value) for value in args if '/negative/' in value]
            paths += [Path(value) for key, value in environment.items() if '/negative/' in value]
            if not paths:
                raise AssertionError('Negative state was not redirected')
            changed = any(path.read_bytes() != bytes(400) if path.is_file() else
                any(item.read_bytes() != bytes(400) for item in path.iterdir() if item.is_file())
                for path in paths)
            if not changed:
                raise AssertionError('Negative state was not changed')
            failure = not self.accept_bad_state
        if self.tamper:
            # A tool that changes canonical bytes must fail before its observations enter the report.
            next(iter(self.runner.seals)).write_bytes(b'changed canonical fixture')
        family = ('synthetic' if 'RAGNAROK_PVM_BENCHMARK' in environment else
                  'guest' if 'RAGNAROK_PVM_SIEVE_EXPECTED' in environment else 'doom')
        # The executable identity selects its role; a parent checkout's name cannot relabel a process.
        engine = 'reference' if args[0] in {str(path) for path in self.runner.references.values()} else 'native'
        if name.endswith('-assertions'):
            diagnostic = {'synthetic': 'pvm synthetic', 'guest': 'pvm sieve', 'doom': 'doom'}[family]
            diagnostic += ' '+engine+' assertion control'
        elif family == 'synthetic':
            diagnostic = 'pvm synthetic terminal register mismatch'
        elif family == 'doom':
            diagnostic = ('DOOM event mismatch' if name.endswith('-events') else
                          'DOOM terminal state mismatch') if engine == 'reference' else (
                          'doom event payload mismatch' if name.endswith('-events') else
                          'doom terminal gas mismatch')
        else:
            diagnostic = 'sieve terminal state mismatch'
        output = 'Assertion Failure: '+diagnostic if failure else 'inert positive protocol'
        if failure and self.unrelated_crash:
            output = 'Segmentation fault'
        return dict(command=args, exit_code=1 if failure else 0, log=name+'.log', output=output)


class InertRunner(performance.PerformanceRunner):
    """Use the production scheduling/control/publication path with inert preparation and parsing seams."""

    def __init__(self, folder, scope='all'):
        """No compiler, subprocess or guest can be reached by this explicitly inert runner."""
        super().__init__(folder, scope)
        self.checks = InertChecks(self)
        self.events = []

    def qualify(self):
        """Supply a known native identity only to exercise later orchestration phases."""
        self.events.append('qualified')
        self.report.update(revision='a'*40, architecture='x86_64')
        compiler = self.folder/'compiler'
        receipt = self.folder/'build/tests/pvm-native/results.json'
        receipt.parent.mkdir(parents=True)
        compiler.write_text('inert compiler identity; never executed')
        receipt.write_text('inert native qualification identity')
        self.seal([compiler, receipt])
        self.report['identity'].update(
            host=dict(system='Linux', architecture='x86_64', machine='x86_64',
                uname=['Linux', 'x86_64'], cpu='inert CPU', runner=dict(RUNNER_ARCH='X64')),
            compiler=dict(sha256=performance.digest(compiler), identity='inert compiler'),
            native_qualification=dict(path='build/tests/pvm-native/results.json',
                                      sha256=performance.digest(receipt),
                                      revision='a'*40),
            ci=dict(GITHUB_RUN_ID='1', GITHUB_RUN_ATTEMPT='2', GITHUB_EVENT_NAME='push',
                GITHUB_REF='refs/heads/master', GITHUB_SHA='a'*40, GITHUB_REPOSITORY='example/pvm',
                GITHUB_JOB='pvm-comparison', PVM_CI_JOB_NAME='Perf / PVM (Linux x86_64)'),
            reference_revision='b'*40, toolchain={}, native_build_defines=['pvmX86Jit'],
            code_lifetime='retained-code-v1')

    def prepare_micro(self):
        """Create independent small placeholders at every canonical input path."""
        self.events.append('micro-prepared')
        self.synthetic_fixture = self.folder/'synthetic.bin'
        self.synthetic_fixture.write_bytes(bytes(400))
        self.references['micro'] = self.folder/'reference-micro'
        self.references['micro'].write_bytes(b'inert reference micro image')
        self.seal([self.references['micro']])
        for case in self.cases:
            if case['family'] == 'guest':
                folder = self.folder/'inputs'/case['case_id']
                folder.mkdir(parents=True)
                data, expected = folder/'input.bin', folder/'expected.bin'
                data.write_bytes(bytes(400))
                expected.write_bytes(bytes(400))
                self.inputs[case['case_id']] = (data, expected)
        self.seal([self.synthetic_fixture, *(path for pair in self.inputs.values() for path in pair)])

    def prepare_doom(self):
        """Provide distinct init/tick state and events without invoking DOOM preparation."""
        self.events.append('doom-prepared')
        self.references['doom'] = self.folder/'reference-doom'
        self.references['doom'].write_bytes(b'inert reference doom image')
        self.seal([self.references['doom']])
        self.report['identity'].update(doom_warmup_ticks=1320,
            doom=dict(warmup_ticks=1320, golden_rgba_sha256='c'*64))
        self.doom_blob, self.rom = self.folder/'doom.polkavm', self.folder/'rom.wad'
        self.doom_folder.mkdir(parents=True)
        for phase in ('init', 'tick'):
            for suffix in ('input', 'expected', 'events'):
                path = self.doom_folder/(phase+'.'+suffix)
                path.write_bytes(bytes(400))
        self.seal(self.doom_folder.iterdir())

    def build_images(self):
        """Represent one image per family; backend identity may only change in the runtime environment."""
        self.events.append('built')
        for family in {case['family'] for case in self.cases}:
            self.images[family] = self.folder/('current-'+family)
            binary = self.images[family]
            binary.write_bytes(b'inert production family image')
            self.seal([binary])
            self.report['builds'].append(dict(family=family, binary=str(binary),
                binary_sha256=performance.digest(binary), defines=['pvmX86Jit']+
                ([] if family == 'synthetic' else ['pvmArm64JitOwnerReceipt']),
                run=dict(exit_code=0)))

    def parse(self, output, case, role):
        """Supply independent normalized observations; protocol parsers have separate focused tests."""
        self.events.append('parsed')
        cases = ([item for item in self.cases if item['family'] == 'synthetic']
                 if case['family'] == 'synthetic' else [case])
        values = {}
        for item in cases:
            execution = dict(preparation_ns=[3], preparation_wall_ns=[5],
                samples=[dict(sample=index, cpu_ns=10+index, wall_ns=40+index) for index in range(13)])
            if role == 'reference':
                label = ('synthetic-'+str(SYNTHETICS.index(item['case_id']))
                         if item['family'] == 'synthetic' else item['case_id'])
                execution['reference_instance'] = retained_instance(label)
            native = policy = None
            if role != 'reference':
                native = dict(fragments=1 if role == 'jit' else 0,
                              calls=13 if role == 'jit' else 0, operations=26 if role == 'jit' else 0)
                policy = dict(version=1, requested=role, actual=role, jit_built=True,
                    platform_supported=True, fallback_enabled=role == 'jit', **native)
            values[item['case_id']] = dict(execution=execution, native=native, policy=policy)
        return values


class PerformanceOrchestrationTests(unittest.TestCase):
    """Protect configured coverage, refusal/identity gates and fresh failure artifacts."""

    def setUp(self):
        """Keep all inert artifacts under the repository's ignored build directory."""
        (ROOT/'build').mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT/'build')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)

    def publish(self, report, folder):
        """Check the complete independent matrix before emulating the report owner's atomic publication."""
        expected = {(case['case_id'], role, order)
                    for case in performance.case_inventory(report['scope'])
                    for role in ('interpreted', 'jit', 'reference') for order in (0, 1)}
        actual = [(row['case_id'], row['role'], row['order']) for row in report['runs']]
        self.assertEqual(len(actual), len(expected))
        self.assertEqual(set(actual), expected)
        self.assertTrue(all(len(row['parsed']['execution']['samples']) == 13 for row in report['runs']))
        report['status'] = 'passed'
        (folder/'results.json').write_text(json.dumps(report))
        (folder/'summary.md').write_text('accepted complete matrix')
        (folder/'samples.csv').write_text('accepted samples')
        return report

    def test_real_publication_accepts_complete_inert_runner_contract(self):
        """The orchestration result and real report API agree on all identity/control/sample fields."""
        runner = InertRunner(self.folder)
        report = runner.execute()
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'passed')
        self.assertIn('CPU', (self.folder/'summary.md').read_text())

    def test_complete_inventory_runtime_policy_pair_and_both_orders(self):
        """Every maintained case has both current policies and interpreted reference in both orders."""
        runner = InertRunner(self.folder)
        self.assertEqual({case['case_id'] for case in runner.cases}, EXPECTED_CASES)
        with patch.object(performance, 'publish_report', side_effect=self.publish), \
                patch.object(performance.subprocess, 'run', side_effect=AssertionError('real process')):
            report = runner.execute()
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(runner.events[:4], ['qualified', 'micro-prepared', 'doom-prepared', 'built'])
        commands = runner.checks.trace
        first_sample = next(i for i, (name, _, _) in enumerate(commands) if '-0-' in name)
        self.assertTrue(all('-positive' in name or name.endswith(('-assertions', '-state', '-events'))
                            for name, _, _ in commands[:first_sample]))
        measured = commands[first_sample:]
        self.assertEqual(len(measured), 12*3*2)
        for order, roles in ((0, ('interpreted', 'jit', 'reference')), (1, ('reference', 'jit', 'interpreted'))):
            group = [(name, args, env) for name, args, env in measured
                     if name.rsplit('-', 2)[1] == str(order)]
            self.assertEqual([name.rsplit('-', 1)[1] for name, _, _ in group[:3]], list(roles))
        interpreted = next(args[0] for name, args, _ in measured if name.endswith('-interpreted'))
        jit = next(args[0] for name, args, _ in measured if name.endswith('-jit'))
        self.assertEqual(interpreted, jit)
        runner.verify()

    def test_scope_selection_has_no_unrequested_preparation_or_runs(self):
        """Micro-only/DOOM-only reuse the same path and exact corresponding configured inventory."""
        for scope, count, excluded in (('micro', 20, 'doom-prepared'), ('doom', 2, 'micro-prepared')):
            with self.subTest(scope=scope):
                runner = InertRunner(self.folder/scope, scope)
                with patch.object(performance, 'publish_report', side_effect=self.publish):
                    report = runner.execute()
                self.assertEqual(len(report['runs']), count*3*2)
                self.assertNotIn(excluded, runner.events)

    def test_bad_state_success_or_unrelated_crash_prevents_all_timing_and_success(self):
        """A refusal gate cannot be supplied by accepting bad state or by a different crash."""
        for failure in ('accept_bad_state', 'unrelated_crash'):
            with self.subTest(failure=failure):
                runner = InertRunner(self.folder/failure, 'doom')
                setattr(runner.checks, failure, True)
                with patch.object(performance, 'publish_report') as publisher:
                    with self.assertRaisesRegex(ValueError, 'intended'):
                        runner.execute()
                publisher.assert_not_called()
                self.assertEqual(runner.report['runs'], [])
                self.assertEqual(json.loads((runner.folder/'results.json').read_text())['status'], 'failed')

    def test_changed_canonical_bytes_and_publication_failure_erase_stale_success(self):
        """Neither a tool mutation nor a rendering error leaves an earlier successful table downloadable."""
        for tamper in (True, False):
            with self.subTest(tamper=tamper):
                runner = InertRunner(self.folder/str(tamper), 'doom')
                runner.folder.mkdir()
                (runner.folder/'summary.md').write_text('old green ratios')
                (runner.folder/'samples.csv').write_text('old accepted samples')
                runner.checks.tamper = tamper
                with patch.object(performance, 'publish_report', side_effect=ValueError('render failed')):
                    with self.assertRaises(ValueError):
                        runner.execute()
                self.assertEqual(runner.report['status'], 'failed')
                self.assertNotIn('old green', (runner.folder/'summary.md').read_text())
                self.assertFalse((runner.folder/'samples.csv').exists())

    def test_inherited_experiment_and_reference_backend_selection_is_discarded(self):
        """A compiled reference override cannot masquerade as the configured interpreted comparison."""
        with patch.dict(os.environ, {'RAGNAROK_PVM_REFERENCE_BACKEND': 'compiler',
            'RAGNAROK_PVM_BACKEND': 'unavailable', 'PVM_JIT_PROCESS_REPLAYS': '1'}):
            env = performance.execution_environment(RAGNAROK_PVM_BACKEND='interpreted')
        self.assertEqual(env['RAGNAROK_PVM_BACKEND'], 'interpreted')
        self.assertNotIn('RAGNAROK_PVM_REFERENCE_BACKEND', env)
        self.assertNotIn('PVM_JIT_PROCESS_REPLAYS', env)

    def test_unrelated_assertion_does_not_replace_the_requested_refusal(self):
        """A genuine assertion in fixture admission is not the requested backend/state/event control."""
        row = dict(exit_code=1, output='Assertion Failure: unrelated setup error')
        for family in ('synthetic', 'guest', 'doom'):
            self.assertFalse(performance.intended_refusal(row, family, 'reference', 'assertions'))
        self.assertFalse(performance.intended_refusal(row, 'doom', 'jit', 'state'))
        self.assertFalse(performance.intended_refusal(row, 'doom', 'reference', 'events'))

    def test_stale_qualification_or_trigger_cannot_reach_builds_or_samples(self):
        """Each prerequisite identity is checked before any compiler or guest launch can occur."""
        for changed in ('trigger', 'revision', 'compiler', 'source', 'empty_sources'):
            with self.subTest(changed=changed):
                root = self.folder/changed
                folder = root/'build/tests/pvm-performance'
                gate = root/'build/tests/pvm-native/results.json'
                gate.parent.mkdir(parents=True)
                source = root/'source.nim'
                source.write_text('inert qualified source')
                compiler = root/'tools-cache/bin/nimony'
                compiler.parent.mkdir(parents=True)
                compiler.write_text('inert compiler')
                host = dict(system='Linux', machine='x86_64', architecture='x86_64')
                receipt = dict(status='passed', revision='a'*40, host=host,
                    compiler_sha256=performance.digest(compiler),
                    policies=dict(native_build_defines=['pvmX86Jit']),
                    sources={'source.nim': performance.digest(source)})
                if changed == 'revision':
                    receipt['revision'] = 'b'*40
                elif changed == 'compiler':
                    compiler.write_text('different compiler')
                elif changed == 'source':
                    source.write_text('different source')
                elif changed == 'empty_sources':
                    receipt['sources'] = {}
                gate.write_text(json.dumps(receipt))
                runner = performance.PerformanceRunner(folder, 'doom',
                    'b'*40 if changed == 'trigger' else 'a'*40)
                with patch.object(performance, 'ROOT', root), \
                        patch.object(performance, 'host_identity', return_value=host), \
                        patch.object(performance, 'installed', return_value=(compiler, None)), \
                        patch.object(performance.subprocess, 'check_output',
                            side_effect=lambda args, **kwargs: 'a'*40 if 'rev-parse' in args else ''), \
                        patch.object(runner, 'build_images') as builds, \
                        patch.object(runner, 'command') as commands, \
                        patch.dict(os.environ, GITHUB_ACTIONS='true', GITHUB_JOB='pvm-comparison',
                                   PVM_CI_JOB_NAME='Perf / PVM (Linux x86_64)'):
                    with self.assertRaises(ValueError):
                        runner.execute()
                builds.assert_not_called()
                commands.assert_not_called()
                self.assertEqual(runner.report['status'], 'failed')
                self.assertEqual(runner.report['runs'], [])

    def test_missing_or_foreign_ci_job_identity_refuses_before_qualification_tools(self):
        """Selective-rerun artifacts require an actual canonical job ID and declared display name."""
        for job, name in ((None, 'PVM job'), ('other-job', 'PVM job'),
                          ('pvm-comparison', None), ('pvm-comparison', ''),
                          ('pvm-comparison', ' \t')):
            with self.subTest(job=job, name=name):
                env = dict(os.environ, GITHUB_ACTIONS='true')
                env.pop('GITHUB_JOB', None)
                env.pop('PVM_CI_JOB_NAME', None)
                if job is not None:
                    env['GITHUB_JOB'] = job
                if name is not None:
                    env['PVM_CI_JOB_NAME'] = name
                runner = performance.PerformanceRunner(self.folder/'job-identity', 'doom')
                with patch.dict(os.environ, env, clear=True), \
                        patch.object(performance, 'host_identity') as host, \
                        patch.object(performance, 'installed') as compiler, \
                        patch.object(runner, 'command') as commands, \
                        patch.object(runner, 'build_images') as builds:
                    with self.assertRaisesRegex(ValueError, 'CI job identity'):
                        runner.execute()
                host.assert_not_called()
                compiler.assert_not_called()
                commands.assert_not_called()
                builds.assert_not_called()
                self.assertEqual(runner.report['runs'], [])
                self.assertEqual(runner.report['status'], 'failed')

    def test_doom_constructor_cpu_wall_and_sample_indices_are_distinct(self):
        """The modern DOOM extension preserves genuine constructor clocks and legacy complete framing."""
        lines = ['API_PREPARE,prepared,7', 'API_PREPARE_WALL,prepared,19']
        lines += [f'DOOM_SAMPLE,native,tick,{index},{100+index},{200+index}' for index in range(13)]
        lines += ['DOOM_OK,native,tick,8', 'PVM_POLICY,1,jit,1,1,1,jit,1,13,26',
                  'ARM_OWNER,tick,1,13,26,64,9,0,0']
        output = '\n'.join(lines)+'\n'
        parsed = performance.parse_application(output, 'jit', 'tick', 0, 8)
        execution = parsed['execution']
        self.assertEqual(execution['preparation_ns'], [7])
        self.assertEqual(execution['preparation_wall_ns'], [19])
        self.assertEqual([item['sample'] for item in execution['samples']], list(range(13)))
        for bad in (output.replace('API_PREPARE_WALL,prepared,19\n', ''),
                    output.replace('prepared,19', 'prepared,0'),
                    output.replace('tick,6,106,206', 'tick,5,106,206')):
            with self.assertRaises(ValueError):
                performance.parse_application(bad, 'jit', 'tick', 0, 8)


if __name__ == '__main__':
    unittest.main()
