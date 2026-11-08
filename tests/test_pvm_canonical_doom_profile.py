# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Qualify canonical host-attribution adaptation with inert processes and literal full-call receipts."""
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_x86_jit_profile as profile
from pvm_performance_fixtures import invocation_observations, REVISION

SOURCE = {'tests/performance/pvm_doom.nim': b'independent driver bytes',
          'src/pvm/step.nim': b'independent engine bytes'}


def digest(data):
    """Seal literal fixture bytes independently of the production adapter."""
    return hashlib.sha256(data).hexdigest()


def cohort(root):
    """Supply complete canonical qualification plus real small input/image files, never real executables."""
    value = json.loads(json.dumps(invocation_observations('doom', 'x86_64')).replace(
        '/sealed/', str(root)+'/'))
    identity = value['identity']
    files = identity['files']
    identity.update(clang='independent pinned Clang', build_environment={})
    for name, data in SOURCE.items():
        # Git archive bytes are mocked separately; source files need not survive artifact cleanup.
        files[str(root/name)] = digest(data)
    binary = root/'current-doom'
    binary.write_bytes(b'independent sealed image')
    files[str(binary)] = digest(binary.read_bytes())
    rom = root/'doom1.wad'
    rom.write_bytes(b'independent ROM')
    files[str(rom)] = digest(rom.read_bytes())
    prepared = root/'prepared'
    prepared.mkdir()
    for case in ('init', 'tick'):
        # Different phases and fixture positions have different bytes, exposing cross-phase substitutions.
        for suffix in ('.input', '.expected', '.events'):
            path = prepared/(case+suffix)
            path.write_bytes((case+suffix).encode())
            files[str(path)] = digest(path.read_bytes())
        for row in value['runs']:
            if row['case'] == case and row['role'] == 'interpreted':
                row['run']['command'] = [str(binary)]
                row['run']['benchmark_environment'] = dict(RAGNAROK_PVM_BACKEND='interpreted',
                    RAGNAROK_PVM_PERFORMANCE='1', RAGNAROK_PVM_DOOM_PRICING='prepared',
                    RAGNAROK_PVM_DOOM_PREPARATION='1', RAGNAROK_PVM_DOOM_TIMING='1',
                    RAGNAROK_PVM_DOOM_ASSERT='0', RAGNAROK_PVM_LOCAL_ONECALL='0',
                    RAGNAROK_PVM_DOOM_INPUT=str(prepared), RAGNAROK_PVM_DOOM_PHASE=case,
                    RAGNAROK_PVM_DOOM_ROM=str(rom), RAGNAROK_PVM_DOOM_LIFECYCLE='0')
    build, = value['builds']
    build['binary_sha256'] = files[str(binary)]
    build['run']['command'] = [str(root/'compiler/nimony'), 'c', '--mm:arc', '--cc:clang',
        '-d:release', '--opt:speed', '--boundchecks:on', '--passC:-flto=thin',
        '--passL:-flto=thin', '--passL:-fuse-ld=lld', '-d:pvmX86Jit',
        '-d:pvmArm64JitOwnerReceipt', '--passC:-I'+str(root/'tests/performance'),
        '--passC:-I'+str(root/'native/pvm_jit'), '--nimcache:'+str(root/'cache'),
        '--out:'+str(binary), str(root/'tests/performance/pvm_doom.nim')]
    return value


def wire(case, event_bytes):
    """Literal original thirteen-call protocol includes honest runtime absence and supplementary clocks."""
    lines = ['PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu',
             'API_PREPARE,prepared,7', 'API_PREPARE_WALL,prepared,19']
    lines += [f'DOOM_SAMPLE,native,{case},{index},{100+index},{200+index}' for index in range(13)]
    lines += [f'DOOM_OK,native,{case},{event_bytes}',
        'PVM_POLICY,1,interpreted,1,1,0,interpreted,0,0,0',
        f'ARM_OWNER,{case},0,0,0,0,0,0,0',
        'PVM_RUNTIME_NONE,1,doom-process,interpreted-policy,1',
        'PVM_OWNER_WINDOW,1,doom-process,100000,200000,includes-driver-oracles',
        'PVM_NATIVE_COMPILATION,1,doom-process,0,0']
    return '\n'.join(lines)+'\n'


def raw_profile(empty=False):
    """Real Callgrind grammar exposes balanced self costs and one preserved child call edge."""
    header = '# callgrind format\npositions: line\nevents: Ir Bc Bcm Bi Bim\n'
    if empty:
        return header+'summary: 0\ntotals: 0\n'
    return (header+'summary: 10 2 1 1\nfn=runPreparedDoom_17_test\n1 3\n'
            'cfn=child\ncalls=1 1\n1 7 2 1 1\nfn=child\n1 7 2 1 1\ntotals: 10 2 1 1\n')


class InertProfileChecks:
    """Return bounded tool evidence and complete raw dumps without starting any process."""

    def __init__(self, folder):
        """Own only this test's diagnostic directory and configurable corruption seams."""
        self.folder = folder
        self.trace = []
        self.missing_part = None
        self.symbols = '100 t runPreparedDoom_17_test\n'
        self.change_input = False
        self.change_tooling = None

    def command(self, arguments, name, environment=None, **options):
        """Emulate observable external-tool outcomes, preserving the production collector's dump validation."""
        args = [str(arg) for arg in arguments]
        self.trace.append((args, environment, options))
        output = ''
        if args == ['valgrind', '--version']:
            output = 'valgrind-3.24.0\n'
        elif args[0] == 'nm':
            output = self.symbols
        elif args[0] == 'valgrind':
            base = Path(next(arg.split('=', 1)[1] for arg in args if arg.startswith('--callgrind-out-file=')))
            base.write_text(raw_profile(True))
            for index in range(1, 14):
                # An omitted intermediate warmup must fail even when the last dump is complete.
                if index != self.missing_part:
                    Path(str(base)+'.'+str(index)).write_text(raw_profile())
            case = environment['RAGNAROK_PVM_DOOM_PHASE']
            events = Path(environment['RAGNAROK_PVM_DOOM_INPUT'])/(case+'.events')
            output = wire(case, events.stat().st_size)
            if self.change_input:
                events.write_bytes(b'changed during instrumentation')
        elif args[0] != 'callgrind_annotate':
            raise AssertionError('Unexpected process attempt: '+str(args))
        log = self.folder/(name+'.log')
        log.write_text(output)
        if self.change_tooling:
            # A tool may not alter diagnostic code and retain a passed receipt under the old seal.
            self.change_tooling.write_bytes(b'changed live diagnostic helper')
        return dict(command=args, exit_code=0, output=output, log=str(log), elapsed_seconds=99999)


class CanonicalDoomProfileTests(unittest.TestCase):
    """Preserve historical behavior while rejecting mixed source, recipe, state and counter authority."""

    def setUp(self):
        """Make a private complete cohort and mocked Git object/archive authority for every test."""
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.value = cohort(self.root)
        self.path = self.root/'cohort.json'
        self.folder = self.root/'profile'
        self.checks = InertProfileChecks(self.folder)
        archive_bytes = io.BytesIO()
        with tarfile.open(fileobj=archive_bytes, mode='w') as archive:
            for name, data in SOURCE.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        self.archive = archive_bytes.getvalue()

    def execute(self, rebuilt=None, value=None):
        """Exercise the real adapter and collector; every possible process boundary remains inert."""
        self.path.write_text(json.dumps(self.value if value is None else value))
        with patch.dict('os.environ', {'GITHUB_ACTIONS': 'true', 'RAGNAROK_PVM_LOCAL_ONECALL': '1',
                                     'PVM_INTERPRETER_TEST': 'foreign'}), \
                patch.object(profile, 'host_identity', return_value=dict(system='Linux', architecture='x86_64')), \
                patch.object(profile, 'NativeChecks', return_value=self.checks), \
                patch.object(profile, 'calibrate_scope'), \
                patch.object(profile.subprocess, 'check_output', side_effect=lambda args, **kw:
                             self.archive if args[1] == 'archive' else 'e'*40+'\n'), \
                patch.object(profile, 'matching_native_activity', side_effect=AssertionError('legacy equality used')):
            return profile.canonical_doom_profile(self.path, REVISION, rebuilt, self.folder)

    def test_original_pair_full_parser_and_no_clock_scores(self):
        """Both complete 13-call processes retain host counters/arcs and discard all instrumented clocks."""
        result = self.execute()
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['image_authority'], 'original-sealed-image')
        self.assertEqual(result['source']['tree'], 'e'*40)
        self.assertEqual([row['case'] for row in result['profiles']], ['init', 'tick'])
        for row in result['profiles']:
            self.assertEqual(row['checked_calls'], 13)
            self.assertEqual(row['runtime'], 'absent')
            self.assertFalse(any(row['native'].values()))
            self.assertEqual(row['cold'], dict(Ir=10, Bc=2, Bcm=1, Bi=1, Bim=0))
            self.assertEqual(row['reused'], row['cold'])
            self.assertEqual(row['self_costs']['child']['Ir'], 7)
            self.assertEqual(len(row['profile_hashes']), 14)
            self.assertTrue((self.folder/(row['case']+'-interpreted-arcs.log')).is_file())
            self.assertNotIn('elapsed_seconds', row['run'])
        derived = json.dumps(result['profiles'])
        for forbidden in ('cpu_ns', 'wall_ns', 'preparation', 'compilation_ns', '99999'):
            self.assertNotIn(forbidden, derived)
        calls = [item for item in self.checks.trace if '--tool=callgrind' in item[0]]
        self.assertEqual(len(calls), 2)
        for args, env, options in calls:
            self.assertIn('--toggle-collect=runPreparedDoom_17_test', args)
            self.assertIn('--dump-after=runPreparedDoom_17_test', args)
            self.assertEqual(options['timeout'], 1200)
            self.assertEqual(env['RAGNAROK_PVM_LOCAL_ONECALL'], '0')
            self.assertEqual(env['RAGNAROK_PVM_PERFORMANCE'], '1')
            self.assertNotIn('PVM_INTERPRETER_TEST', env)

    def test_incomplete_legacy_foreign_source_isa_and_recipes_refuse(self):
        """Valid JSON and a plausible executable cannot substitute for the selected current full cohort."""
        mutations = (
            lambda value: value.update(schema='pvm-performance-v2'),
            lambda value: value.update(status='incomplete'),
            lambda value: value.update(revision='f'*40),
            lambda value: value.update(architecture='arm64'),
            lambda value: value['runs'].pop(),
            lambda value: value['controls'].pop(),
            lambda value: value['builds'][0]['run']['command'].insert(2, '--boundchecks:off'),
            lambda value: value['runs'][0]['run']['benchmark_environment'].update(RAGNAROK_PVM_PERFORMANCE='0'),
            lambda value: value['identity']['files'].pop(str(self.root/'prepared/init.input')),
            lambda value: value['identity']['files'].update({str(self.root/'src/pvm/step.nim'): 'f'*64}),
        )
        for mutate in mutations:
            value = deepcopy(self.value)
            mutate(value)
            with self.subTest(mutation=mutate), self.assertRaises(ValueError):
                self.execute(value=value)
        self.assertEqual(self.checks.trace, [])

    def test_rebuilt_report_qualifies_its_own_image_without_original_bytes(self):
        """Omitted historical executables are allowed only with explicit independently passed rebuild evidence."""
        rebuilt_root = self.root/'rebuilt'
        rebuilt_root.mkdir()
        rebuilt = cohort(rebuilt_root)
        rebuilt_binary = rebuilt_root/'current-doom'
        rebuilt_binary.write_bytes(b'independently rebuilt diagnostic image')
        new_hash = digest(rebuilt_binary.read_bytes())
        rebuilt['identity']['files'][str(rebuilt_binary)] = new_hash
        rebuilt['builds'][0]['binary_sha256'] = new_hash
        rebuilt_path = self.root/'rebuilt.json'
        rebuilt_path.write_text(json.dumps(rebuilt))
        (self.root/'current-doom').unlink()
        with self.assertRaises(ValueError):
            self.execute()
        result = self.execute(rebuilt_path)
        self.assertEqual(result['image_authority'], 'independent-rebuild')
        self.assertEqual(result['image']['sha256'], new_hash)
        self.assertEqual(len(result['cohorts']), 2)
        rebuilt['identity']['files'][str(rebuilt_root/'prepared/tick.input')] = 'f'*64
        rebuilt_path.write_text(json.dumps(rebuilt))
        self.checks.trace.clear()
        with self.assertRaisesRegex(ValueError, 'input seals'):
            self.execute(rebuilt_path)
        self.assertEqual(self.checks.trace, [])

    def test_missing_dump_scope_and_changed_live_bytes_fail_closed(self):
        """Real collector validation and input seals reject truncated return sequences and altered fixtures."""
        self.checks.missing_part = 6
        with self.assertRaises(ValueError):
            self.execute()
        self.checks.missing_part = None
        self.checks.symbols = ' U runPreparedDoom_17_test\n'
        with self.assertRaisesRegex(ValueError, 'symbol'):
            self.execute()
        self.checks.symbols = '100 t runPreparedDoom_17_test\n'
        self.checks.change_input = True
        with self.assertRaisesRegex(ValueError, 'changed during run'):
            self.execute()
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')

    def test_image_tampering_and_calibration_failure_never_publish_success(self):
        """A changed original image and failed mandatory controls must retire any previous passed report."""
        binary = self.root/'current-doom'
        original = binary.read_bytes()
        binary.write_bytes(b'changed sealed image')
        with self.assertRaisesRegex(ValueError, 'changed during run'):
            self.execute()
        self.assertEqual(self.checks.trace, [])
        binary.write_bytes(original)
        self.folder.mkdir(exist_ok=True)
        destination = self.folder/'results.json'
        destination.write_text('{"status":"passed"}')

        def interrupted(checks, report):
            """An interruption after tool entry must observe and leave explicit non-success metadata."""
            self.assertEqual(json.loads(destination.read_text())['status'], 'incomplete')
            raise KeyboardInterrupt('bounded test interruption')

        self.path.write_text(json.dumps(self.value))
        with patch.dict('os.environ', {'GITHUB_ACTIONS': 'true'}), \
                patch.object(profile, 'host_identity', return_value=dict(system='Linux', architecture='x86_64')), \
                patch.object(profile, 'NativeChecks', return_value=self.checks), \
                patch.object(profile, 'calibrate_scope', side_effect=interrupted), \
                patch.object(profile.subprocess, 'check_output', side_effect=lambda args, **kw:
                             self.archive if args[1] == 'archive' else 'e'*40+'\n'):
            with self.assertRaises(KeyboardInterrupt):
                profile.canonical_doom_profile(self.path, REVISION, folder=self.folder)
        self.assertEqual(json.loads(destination.read_text())['status'], 'failed')
        self.assertEqual([args for args, _, _ in self.checks.trace], [['valgrind', '--version']])

    def test_full_call_runtime_native_and_oracle_refusals(self):
        """A missing scope/runtime receipt, leaked native operation or wrong terminal oracle cannot pass."""
        output = wire('tick', 8)
        self.assertEqual(profile.canonical_doom_observation(output, 'tick', 8)['checked_calls'], 13)
        for bad in (
            output.partition('\n')[2],
            output.replace('PVM_RUNTIME_NONE,1,doom-process,interpreted-policy,1\n', ''),
            output.replace('PVM_RUNTIME_NONE,1,doom-process,interpreted-policy,1',
                           'PVM_RUNTIME_OWNER,1,doom-process,application-process,demand-started,1'),
            output.replace('interpreted,0,0,0\n', 'jit,1,13,26\n').replace(
                'ARM_OWNER,tick,0,0,0,0,0,0,0', 'ARM_OWNER,tick,1,13,26,64,0,0,0'),
            output.replace('DOOM_OK,native,tick,8', 'DOOM_OK,native,tick,9'),
            output.replace('tick,6,106,206', 'tick,5,106,206'),
            output.replace('PVM_NATIVE_COMPILATION,1,doom-process,0,0',
                           'PVM_NATIVE_COMPILATION,1,doom-process,1,7'),
        ):
            with self.subTest(receipt=bad), self.assertRaises(ValueError):
                profile.canonical_doom_observation(bad, 'tick', 8)

    def test_actual_tooling_closure_and_changed_helper_refuse(self):
        """Collector, parser and control identities accompany product seals and cannot drift during tools."""
        tooling = profile.canonical_tooling_seals()
        for name in ('tools/pvm_x86_jit_profile.py', 'tools/pvm_instruction_profile.py',
                     'tools/pvm_ci_performance.py', 'tools/pvm_invocation_scope.py',
                     'tools/pvm_arm64_jit_applications.py', 'tools/native_checks.py',
                     'tests/support/pvm_profile_control.c'):
            self.assertIn(profile.ROOT/name, tooling)
        copied_helper = self.root/'diagnostic-control.c'
        copied_helper.write_bytes(b'independent control source')
        tooling[copied_helper] = digest(copied_helper.read_bytes())
        self.checks.change_tooling = copied_helper
        with patch.object(profile, 'canonical_tooling_seals', return_value=tooling):
            with self.assertRaisesRegex(ValueError, 'changed during run'):
                self.execute()
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')
        self.assertEqual([args for args, _, _ in self.checks.trace], [['valgrind', '--version']])

    def test_non_ci_refusal_happens_before_tools(self):
        """Observing or running pure tests locally never authorizes a profiler process."""
        with patch.dict('os.environ', {'GITHUB_ACTIONS': 'false'}), \
                patch.object(profile, 'NativeChecks') as checks:
            with self.assertRaisesRegex(RuntimeError, 'CI-only'):
                profile.canonical_doom_profile(self.path, REVISION, folder=self.folder)
            checks.assert_not_called()


if __name__ == '__main__':
    unittest.main()
