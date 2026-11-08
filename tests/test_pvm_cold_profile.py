# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise cold scope/image/workload boundaries with literal protocols and inert collectors only."""
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import tarfile
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import pvm_cold_profile as profile
import pvm_x86_jit_profile as maintained
from pvm_performance_fixtures import invocation_observations, REVISION

SOURCE = {'tests/performance/pvm_sieve.nim': b'independent canonical guest driver',
          'src/pvm/step.nim': b'independent product source'}


def digest(data):
    """Bind literal test evidence independently of the adapter's qualification logic."""
    return hashlib.sha256(data).hexdigest()


def cohort(root):
    """Keep a complete canonical micro cohort plus small real input/image files, never executables."""
    value = json.loads(json.dumps(invocation_observations('micro', 'x86_64')).replace(
        '/sealed/', str(root)+'/'))
    identity = value['identity']
    files = identity['files']
    identity.update(clang='independent pinned Clang', build_environment={})
    for name, data in SOURCE.items():
        files[str(root/name)] = digest(data)
    binary = root/'current-guest'
    binary.write_bytes(b'inert sealed image; not executable')
    files[str(binary)] = digest(binary.read_bytes())
    data, expected = root/'sieve.input', root/'sieve.expected'
    header = bytearray(136)
    header[:8] = b'PVMSIV01'
    header[16:20] = (1000).to_bytes(4, 'little')
    data.write_bytes(header)
    expected.write_bytes(b'independent state oracle')
    artifact = root/'tests/fixtures/pvm-sieve/sieve.polkavm'
    artifact.parent.mkdir(parents=True)
    artifact.write_bytes(b'independent compact artifact')
    for path in (data, expected, artifact):
        files[str(path)] = digest(path.read_bytes())
    for row in value['runs']:
        if row['case_id'] == 'sieve-1000' and row['role'] == 'interpreted':
            row['run']['command'] = [str(binary)]
            row['run']['benchmark_environment'] = dict(RAGNAROK_PVM_BACKEND='interpreted',
                RAGNAROK_PVM_PERFORMANCE='1', RAGNAROK_PVM_GUEST='sieve',
                RAGNAROK_PVM_PRICING='prepared', RAGNAROK_PVM_SIEVE_SAMPLES='13',
                RAGNAROK_PVM_SIEVE_CLOCK='1', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',
                RAGNAROK_PVM_SIEVE_INPUT=str(data), RAGNAROK_PVM_SIEVE_EXPECTED=str(expected),
                RAGNAROK_PVM_SIEVE_ARTIFACT=str(artifact))
    build, = [row for row in value['builds'] if row['family'] == 'guest']
    build['binary_sha256'] = files[str(binary)]
    build['run']['command'] = [str(root/'compiler/nimony'), 'c', '--mm:arc', '--cc:clang',
        '-d:release', '--opt:speed', '--boundchecks:on', '--passC:-flto=thin',
        '--passL:-flto=thin', '--passL:-fuse-ld=lld', '-d:pvmX86Jit',
        '-d:pvmArm64JitOwnerReceipt', '--passC:-I'+str(root/'tests/performance'),
        '--passC:-I'+str(root/'native/pvm_jit'), '--nimcache:'+str(root/'cache'),
        '--out:'+str(binary), str(root/'tests/performance/pvm_sieve.nim')]
    return value


def wire():
    """Literal prepared/full-call grammar carries all13 observations and explicit absent runtime."""
    lines = ['PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu',
             'PREPARED_PROGRAM,7,19,32,1']
    for index in range(13):
        lines += [f'SIEVE,ragnarok_prepared,1000,{index},{200+index},{100+index}',
                  f'PREPARED_CACHE,{index},1,1,8388608,67108864']
    lines += ['PVM_POLICY,1,interpreted,1,1,0,interpreted,0,0,0',
        'ARM_OWNER,sieve,0,0,0,0,0,0,0',
        'PVM_RUNTIME_NONE,1,guest-process,interpreted-policy,1',
        'PVM_OWNER_WINDOW,1,guest-process,100000,200000,includes-driver-oracles',
        'PVM_NATIVE_COMPILATION,1,guest-process,0,0']
    return '\n'.join(lines)+'\n'


def raw_profile(symbol, index=0):
    """Return balanced complete host counters with distinct return costs, or an empty final dump."""
    header = '# callgrind format\npositions: line\nevents: Ir Bc Bcm Bi Bim\n'
    if index == 0:
        return header+'summary: 0\ntotals: 0\n'
    return (header+f'summary: {10+index} 2 1 1\nfn={symbol}\n1 {3+index}\n'
        f'cfn=child\ncalls=1 1\n1 7 2 1 1\nfn=child\n1 7 2 1 1\ntotals: {10+index} 2 1 1\n')


class InertChecks:
    """Observe the real collector argv and generate bounded text dumps without any subprocess."""

    def __init__(self, folder):
        """Own this test's tool trace and independently specified1/1/13 symbol cardinalities."""
        self.folder = folder
        self.trace = []
        self.returns = {'decodeArtifact_1_test': 1, 'prepareIndependent_2_test': 1,
                        'runPreparedKernel_3_test': 13}
        self.symbols = ''.join(f'100 t {name}\n' for name in self.returns)
        self.output = wire()
        self.missing = None
        self.extra = None
        self.changed = None
        self.exit_code = 0

    def command(self, arguments, name, environment=None, **options):
        """Supply only declared tool observations; any other attempted command fails the test."""
        args = [str(arg) for arg in arguments]
        self.trace.append((args, environment, options))
        text = ''
        exit_code = 0
        if args == ['valgrind', '--version']:
            text = 'valgrind-3.24.0\n'
        elif args[0] == 'nm':
            text = self.symbols
        elif args[0] == 'valgrind':
            scope = next(arg.split('=', 1)[1] for arg in args if arg.startswith('--toggle-collect='))
            output = Path(next(arg.split('=', 1)[1] for arg in args if arg.startswith('--callgrind-out-file=')))
            output.write_text(raw_profile(scope))
            for index in range(1, self.returns[scope]+1):
                if self.missing != (scope, index):
                    Path(str(output)+'.'+str(index)).write_text(raw_profile(scope, index))
            if self.extra == scope:
                Path(str(output)+'.'+str(self.returns[scope]+1)).write_text(raw_profile(scope, 20))
            text, exit_code = self.output, self.exit_code
            if self.changed:
                self.changed.write_bytes(b'changed during instrumentation')
        elif args[0] != 'callgrind_annotate':
            raise AssertionError('Unexpected execution: '+str(args))
        log = self.folder/(name+'.log')
        log.write_text(text)
        return dict(command=args, exit_code=exit_code, output=text, log=str(log), elapsed_seconds=99999)


class ColdProfileTests(unittest.TestCase):
    """Refuse wrong qualification, scope/cardinality, workload or mutable evidence without execution."""

    def setUp(self):
        """Provide independent source archive, live authority bytes and a complete canonical cohort."""
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.value = cohort(self.root)
        self.path = self.root/'cohort.json'
        self.folder = self.root/'profile'
        self.checks = InertChecks(self.folder)
        self.helper = self.root/'live-helper.py'
        self.helper.write_bytes(b'inert sealed live helper')
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w') as archive:
            for name, content in SOURCE.items():
                member = tarfile.TarInfo(name)
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
        self.archive = data.getvalue()

    def execute(self, value=None, calibration_error=None, host=None, rebuilt=None):
        """Exercise actual admission/parsing/collector code while every tool/build boundary is inert."""
        # A real attempt creates fresh NativeChecks; do not stack prior attempts' sealed wrappers.
        self.checks.command = InertChecks.command.__get__(self.checks, InertChecks)
        self.path.write_text(json.dumps(self.value if value is None else value))
        with patch.dict('os.environ', GITHUB_ACTIONS='true', PVM_INTERPRETER_TEST='foreign'), \
                patch.object(profile, 'host_identity', return_value=host or dict(system='Linux', architecture='x86_64')), \
                patch.object(profile, 'NativeChecks', return_value=self.checks), \
                patch.object(profile, 'calibrate_scope', side_effect=calibration_error), \
                patch.object(profile, 'canonical_tooling_seals', return_value={self.helper:digest(self.helper.read_bytes())}), \
                patch.object(maintained.subprocess, 'check_output', side_effect=lambda args, **kw:
                             self.archive if args[1] == 'archive' else 'e'*40+'\n'):
            return profile.profile_sieve(self.path, REVISION, rebuilt, self.folder)

    def test_three_scopes_preserve_one_one_thirteen_and_complete_workload_without_clock_scores(self):
        """Each constructor still executes the entire process; return13 remains a named final return."""
        result = self.execute()
        self.assertEqual(result['status'], 'passed')
        self.assertEqual([row['expected_returns'] for row in result['profiles']], [1, 1, 13])
        self.assertEqual([len(row['parts']) for row in result['profiles']], [1, 1, 13])
        self.assertEqual(result['profiles'][2]['parts'][0]['counts']['Ir'], 11)
        self.assertEqual(result['profiles'][2]['parts'][12]['counts']['Ir'], 23)
        for row in result['profiles']:
            self.assertEqual(row['checked_calls'], 13)
            self.assertEqual(row['runtime'], 'absent')
            self.assertFalse(any(row['native'].values()))
            self.assertEqual(row['run']['cwd'], str(self.root))
            self.assertNotIn('elapsed_seconds', row['run'])
        for field in ('cpu_ns', 'wall_ns', 'preparation', 'compilation_ns', '99999', 'reused'):
            self.assertNotIn(field, json.dumps(result['profiles']))
        executions = [item for item in self.checks.trace if '--tool=callgrind' in item[0]]
        self.assertEqual(len(executions), 3)
        for args, env, options in executions:
            self.assertEqual(options['timeout'], 1200)
            self.assertEqual(options['cwd'], self.root)
            self.assertEqual(env['RAGNAROK_PVM_SIEVE_SAMPLES'], '13')
            self.assertEqual(env['RAGNAROK_PVM_SIEVE_CLOCK'], '1')
            self.assertEqual(env['RAGNAROK_PVM_BACKEND'], 'interpreted')
            self.assertNotIn('PVM_INTERPRETER_TEST', env)

    def test_foreign_reports_sources_recipes_and_workloads_refuse_before_collection(self):
        """Labels/retagging cannot replace complete current authority and the exact original recipe."""
        mutations = (
            lambda v: v.update(schema='pvm-source-comparison-cohort-v1'),
            lambda v: v.update(schema='pvm-performance-v2'),
            lambda v: v.update(status='incomplete'),
            lambda v: v.update(revision='f'*40),
            lambda v: v.update(architecture='arm64'),
            lambda v: v['runs'].pop(),
            lambda v: v['controls'].pop(),
            lambda v: v['identity']['files'].update({str(self.root/'src/pvm/step.nim'):'f'*64}),
            lambda v: next(b for b in v['builds'] if b['family']=='guest')['run']['command'].insert(2,'--boundchecks:off'),
            lambda v: next(r for r in v['runs'] if r['case_id']=='sieve-1000' and r['role']=='interpreted' and r['order']==0)['run']['benchmark_environment'].update(RAGNAROK_PVM_SIEVE_SAMPLES='4'),
            lambda v: v['identity']['files'].pop(str(self.root/'sieve.input')),
        )
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                value = deepcopy(self.value)
                mutate(value)
                with self.assertRaises(ValueError):
                    self.execute(value)
        self.assertEqual(self.checks.trace, [])

    def test_resealed_different_sieve_size_is_not_the_selected_cold_workload(self):
        """Even coherent byte seals cannot turn a Sieve10000 input into a Sieve1000 profile."""
        path = self.root/'sieve.input'
        data = bytearray(path.read_bytes())
        data[16:20] = (10000).to_bytes(4,'little')
        path.write_bytes(data)
        self.value['identity']['files'][str(path)] = digest(data)
        with self.assertRaisesRegex(ValueError, 'not Sieve1000'):
            self.execute()
        self.assertEqual(self.checks.trace, [])

    def test_absent_ambiguous_symbols_and_missing_or_extra_return_parts_refuse(self):
        """A valid final output cannot hide wrong Linux symbol selection or1/13 dump boundaries."""
        self.checks.symbols += '200 t decodeArtifact_2_clone\n'
        with self.assertRaises(ValueError):
            self.execute()
        self.checks.symbols = '100 t decodeArtifact_1_test\n'
        with self.assertRaises(ValueError):
            self.execute()
        self.checks.symbols = ''.join(f'100 t {name}\n' for name in self.checks.returns)
        for scope, index in [('decodeArtifact_1_test',1),('runPreparedKernel_3_test',7)]:
            self.checks.missing = (scope,index)
            with self.assertRaisesRegex(ValueError, 'function-return dumps'):
                self.execute()
        self.checks.missing = None
        self.checks.extra = 'prepareIndependent_2_test'
        with self.assertRaisesRegex(ValueError, 'function-return dumps'):
            self.execute()

    def test_full_state_parser_native_zero_and_process_exit_remain_mandatory(self):
        """Counter dumps cannot rescue incomplete calls, wrong policy, native work or a failed process."""
        for text in (wire().replace('SIEVE,ragnarok_prepared,1000,7,207,107\n',''),
                     wire().replace('ARM_OWNER,sieve,0,0,0,0,0,0,0','ARM_OWNER,sieve,1,1,1,1,0,0,0'),
                     wire().replace('PVM_RUNTIME_NONE','PVM_RUNTIME_OWNER')):
            self.checks.output = text
            with self.assertRaises(ValueError):
                self.execute()
        self.checks.output = wire()
        self.checks.exit_code = 2
        with self.assertRaisesRegex(RuntimeError, 'tool failed'):
            self.execute()
        failed = json.loads((self.folder/'results.json').read_text())
        self.assertEqual(failed['status'], 'failed')

    def test_changed_input_and_live_helper_fail_the_original_seal(self):
        """Guest data, executable and imported helpers stay immutable across an instrumented child."""
        for path in (self.root/'sieve.input', self.root/'current-guest', self.helper):
            with self.subTest(path=path):
                original = path.read_bytes()
                self.checks.changed = path
                with self.assertRaises(ValueError):
                    self.execute()
                path.write_bytes(original)

    def test_independently_qualified_rebuild_is_explicit_and_input_identical(self):
        """A missing original image needs separate current qualification, never an implicit rebuild."""
        rebuilt = self.root/'rebuilt'
        rebuilt.mkdir()
        value = cohort(rebuilt)
        binary = rebuilt/'current-guest'
        binary.write_bytes(b'different independently qualified image')
        value['identity']['files'][str(binary)] = digest(binary.read_bytes())
        next(b for b in value['builds'] if b['family']=='guest')['binary_sha256'] = digest(binary.read_bytes())
        path = rebuilt/'cohort.json'
        path.write_text(json.dumps(value))
        (self.root/'current-guest').unlink()
        result = self.execute(rebuilt=path)
        self.assertEqual(result['image_authority'], 'independent-rebuild')
        self.assertEqual(result['image']['path'], str(binary))
        self.assertEqual(result['image']['sha256'], digest(binary.read_bytes()))
        self.checks.trace.clear()
        expected = rebuilt/'sieve.expected'
        expected.write_bytes(b'foreign input oracle')
        value['identity']['files'][str(expected)] = digest(expected.read_bytes())
        path.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, 'input seals disagree'):
            self.execute(rebuilt=path)
        self.assertEqual(self.checks.trace, [])

    def test_absent_image_foreign_host_and_calibration_failure_start_no_guest(self):
        """No fallback build or alternate host/scope can certify the current unchanged image."""
        with self.assertRaisesRegex(ValueError, 'native Linux'):
            self.execute(host=dict(system='Darwin',architecture='x86_64'))
        self.assertEqual(self.checks.trace, [])
        with self.assertRaisesRegex(RuntimeError, 'inert calibration failure'):
            self.execute(calibration_error=RuntimeError('inert calibration failure'))
        self.assertFalse(any('--tool=callgrind' in args for args,_,_ in self.checks.trace))
        (self.root/'current-guest').unlink()
        self.checks.trace.clear()
        with self.assertRaisesRegex(ValueError, 'absent; no implicit rebuild'):
            self.execute()
        self.assertEqual(self.checks.trace, [])
