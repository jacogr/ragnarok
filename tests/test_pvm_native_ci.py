# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Refuse mismatched CI hosts and missing native execution before accepting PVM qualification."""
from contextlib import ExitStack
from pathlib import Path
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_native_ci as ci
from pvm_arm64_jit import qualify


class NativeHostTests(unittest.TestCase):
    def host(self, machine='aarch64', declared='arm64', runner='ARM64', uname=None):
        """Use real pinned platform metadata with mocked process/Actions host identities."""
        with ExitStack() as stack:
            stack.enter_context(patch.dict(os.environ, dict(GITHUB_ACTIONS='true', PVM_CI_SYSTEM='Linux',
                PVM_CI_ARCH=declared, RUNNER_ARCH=runner), clear=True))
            stack.enter_context(patch('pvm_native_ci.platform.system', return_value='Linux'))
            stack.enter_context(patch('pvm_native_ci.platform.machine', return_value=machine))
            stack.enter_context(patch('pvm_native_ci.subprocess.check_output', return_value=uname or 'Linux '+machine))
            stack.enter_context(patch('pvm_native_ci.Path.exists', return_value=False))
            stack.enter_context(patch('pvm_native_ci.platform.platform', return_value='native-host'))
            return ci.host_identity()

    def test_two_linux_archive_selections(self):
        """Actual host architecture selects the official matching pin, independently of display names."""
        for machine,arch,runner,pin in [('aarch64','arm64','ARM64','linux_arm64'),
                                        ('x86_64','x86_64','X64','linux_amd64')]:
            with self.subTest(arch=arch):
                report=self.host(machine,arch,runner)
                self.assertEqual(report['toolchain_platform'],pin)
                self.assertEqual(report['architecture'],arch)

    def test_production_flag_plan_selects_its_native_gates(self):
        """Ordinary x86 CI must execute x86 lowering gates, while ARM and unsupported-host controls retain their proper paths."""
        for system,machine,x86,native in (('Linux','x86_64',True,True),
            ('Linux','aarch64',False,True), ('Darwin','arm64',False,True),
            ('Darwin','x86_64',False,False)):
            with self.subTest(system=system,machine=machine), patch.object(ci,'qualify_x86',return_value=['x86']) as xgate, patch.object(ci,'qualify',return_value=['arm']) as agate:
                checks,compiler=object(),object()
                result=ci.qualify_host(checks,compiler,dict(system=system,machine=machine))
                self.assertEqual(result,['x86'] if x86 else ['arm'])
                if x86:
                    xgate.assert_called_once_with(checks,compiler);agate.assert_not_called()
                else:
                    agate.assert_called_once_with(checks,compiler,native=native);xgate.assert_not_called()

    def test_foreign_declared_runner_and_uname(self):
        """Neither a mislabeled runner nor emulated/mismatched process can claim the requested native host."""
        for kwargs in [dict(declared='x86_64'),dict(runner='X64'),dict(uname='Linux x86_64'),
                       dict(machine='mips')]:
            with self.subTest(kwargs=kwargs),self.assertRaises(ValueError):
                self.host(**kwargs)

    def test_missing_ci_declaration_and_container(self):
        """Actions must declare the expected host and cannot substitute a container for native timing."""
        with patch.dict(os.environ, {'GITHUB_ACTIONS':'true'},clear=True):
            with self.assertRaisesRegex(ValueError,'Missing declared'):
                ci.host_identity()
        with patch.dict(os.environ, dict(GITHUB_ACTIONS='true',PVM_CI_SYSTEM='Linux',
                         PVM_CI_ARCH='arm64',RUNNER_ARCH='ARM64'),clear=True), \
             patch('pvm_native_ci.platform.system',return_value='Linux'), \
             patch('pvm_native_ci.platform.machine',return_value='aarch64'), \
             patch('pvm_native_ci.subprocess.check_output',return_value='Linux aarch64'), \
             patch('pvm_native_ci.Path.exists',return_value=True):
            with self.assertRaisesRegex(ValueError,'Container execution'):
                ci.host_identity()

    def test_failed_run_replaces_previous_success(self):
        """A failed preflight leaves current incomplete evidence rather than stale green results."""
        with tempfile.TemporaryDirectory() as folder,patch.object(ci,'BUILD',Path(folder)), \
             patch.object(ci,'host_identity',side_effect=ValueError('wrong host')):
            destination=Path(folder)/'results.json'
            destination.write_text('{"status":"passed"}')
            with self.assertRaisesRegex(ValueError,'wrong host'):
                ci.run()
            self.assertIn('"status": "incomplete"',destination.read_text())
            self.assertIn('wrong host',destination.read_text())


class PolicyQualificationTests(unittest.TestCase):
    """Exercise registered resident/scalar qualification and retained evidence with inert outcomes."""

    def setUp(self):
        """Create independent source/header/profile contracts; no compiler or executable is invoked."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.live = self.root/'live-evidence'
        self.live.mkdir()
        self.folder = self.root/'native-artifact'
        self.folder.mkdir()
        self.compiler = self.root/'tool/bin/nimony'
        self.compiler.parent.mkdir(parents=True)
        self.compiler.write_bytes(b'inert compiler')
        (self.compiler.parent.parent/'NIGHTLY.txt').write_text('inert pinned identity')
        self.profiles = {suite: dict(directory='codec', libraries=[], includes=[], observers=[],
            defines=['pvmResidentWitness'], prepared=False)
            for suite in ('pvm_fresh_resident', 'pvm_resident_bytes')}
        self.profiles.update(
            pvm_accumulation_scalar_host=dict(directory='state', libraries=['observer'],
                includes=['crypto'], observers=[], defines=[], prepared=False),
            pvm_scalar_host=dict(directory='codec', libraries=[], includes=[], observers=[],
                defines=[], prepared=False))
        self.arc_suites = {'pvm_fresh_resident', 'pvm_resident_bytes', 'pvm_scalar_host'}
        self.inputs = ['src/pvm/internal/resident_bytes.nim',
            'src/pvm/internal/resident_capture.nim', 'src/pvm/internal/resident_os.h',
            'tests/support/arc_evidence.nim', 'tests/support/pvm_accumulation_context.nim',
            'tests/support/pvm_accumulation_program.nim']
        for suite, profile in self.profiles.items():
            directory = profile['directory']
            self.inputs.extend(('tests/unit/'+directory+'/test_'+suite+'.nim',
                'tests/unit/'+directory+'/test_'+suite+'.output',
                'tools/native_requirements/'+directory+'/'+suite+'.json'))
        for relative in self.inputs:
            target = self.root/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('independent qualification input: '+relative)
        for suite, profile in self.profiles.items():
            (self.root/'tools/native_requirements'/profile['directory']/(suite+'.json')).write_text(
                json.dumps(profile))
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(ci, 'ROOT', self.root))
        self.stack.enter_context(patch.object(ci, 'NATIVE_REQUIREMENTS', self.profiles))
        self.stack.enter_context(patch.object(ci, 'unit_source', side_effect=lambda suite:
            self.root/'tests/unit'/self.profiles[suite]['directory']/('test_'+suite+'.nim')))
        self.stack.enter_context(patch.object(ci, 'unit_evidence_directory', return_value=self.live))
        self.proof = dict(cycles=1000, occupied_before=192, occupied_after=192)
        self.emit = True
        self.tamper = None
        self.checks = Mock(folder=self.folder)
        self.checks.command.side_effect = self.suite_result

    def suite_result(self, arguments, name, **options):
        """Only a newly emitted numeric observation can stand in for successful maintained execution."""
        suite = arguments[arguments.index('--suite')+1]
        if suite in self.profiles:
            if self.emit and suite in self.arc_suites:
                (self.live/(suite+'.json')).write_text(json.dumps(self.proof))
            if self.tamper:
                (self.root/self.tamper).write_text('changed during qualification')
        return dict(exit_code=0, log='policy.log')

    def test_registered_resident_scalar_units_and_fresh_arc_are_required(self):
        """Both shared-refusal policies run each new unit once and retain ARC after original files disappear."""
        for shared in (False, True):
            with self.subTest(shared=shared):
                self.checks.command.reset_mock()
                rows = ci.qualify_policy(self.checks, self.compiler, shared_refusal=shared)
                expected = ['pvm_memory_reuse', 'pvm_runtime_policy',
                    'pvm_fresh_resident', 'pvm_resident_bytes',
                    'pvm_accumulation_scalar_host', 'pvm_scalar_host']
                if not shared:
                    expected.append('pvm_runtime_policy_refused')
                self.assertCountEqual([row['suite'] for row in rows], expected)
                selected = [call.args[0][call.args[0].index('--suite')+1]
                    for call in self.checks.command.call_args_list]
                self.assertCountEqual(selected, expected)
                for row in rows:
                    if row['suite'] in self.profiles:
                        for relative in self.inputs:
                            self.assertEqual(row['sources'][relative],
                                ci.hashlib.sha256((self.root/relative).read_bytes()).hexdigest())
                    if row['suite'] in self.arc_suites:
                        (self.live/(row['suite']+'.json')).unlink()
                        retained = Path(row['arc_evidence'])
                        self.assertEqual(retained.parent, self.folder)
                        self.assertEqual(json.loads(retained.read_text()), self.proof)
                        self.assertEqual(row['arc'], self.proof)
                        self.assertEqual(row['arc_evidence_sha256'], ci.hashlib.sha256(retained.read_bytes()).hexdigest())
                        self.assertIn('src/pvm/internal/resident_os.h', row['sources'])
                    if row['suite'] == 'pvm_accumulation_scalar_host':
                        self.assertNotIn('arc', row)
                        self.assertNotIn('arc_evidence', row)

    def test_failed_suite_prevents_qualification(self):
        """A failed maintained unit cannot produce a green policy qualification."""
        self.checks.command.side_effect = None
        self.checks.command.return_value = dict(exit_code=1, log='failure.log')
        with self.assertRaisesRegex(RuntimeError, 'failure.log'):
            ci.qualify_policy(self.checks, self.compiler)

    def test_zero_exit_cannot_reuse_stale_arc(self):
        """A green child without fresh evidence cannot accept old live or previously retained observations."""
        for suite in self.profiles:
            (self.live/(suite+'.json')).write_text(json.dumps(self.proof))
            (self.folder/(suite+'.json')).write_text(json.dumps(self.proof))
        self.emit = False
        with self.assertRaises(FileNotFoundError):
            ci.qualify_policy(self.checks, self.compiler)

    def test_failed_arc_suite_retains_fresh_invalid_arc(self):
        """The maintained launcher can reject ARC itself; its nonzero exit must not discard raw proof."""
        invalid = b'{invalid fresh ARC observation'

        for target in ('pvm_fresh_resident', 'pvm_scalar_host'):
            with self.subTest(suite=target):
                def rejected(arguments, name, **options):
                    suite = arguments[arguments.index('--suite')+1]
                    if suite == target:
                        (self.live/(suite+'.json')).write_bytes(invalid)
                        return dict(exit_code=1, log='arc-failure.log')
                    return self.suite_result(arguments, name, **options)

                self.checks.command.side_effect = rejected
                with self.assertRaisesRegex(RuntimeError, 'arc-failure.log'):
                    ci.qualify_policy(self.checks, self.compiler)
                self.assertEqual((self.folder/(target+'.json')).read_bytes(), invalid)

    def test_either_scalar_child_failure_prevents_qualification(self):
        """The actual product main and mixed scalar main must each succeed through the registered launcher."""
        for target in ('pvm_accumulation_scalar_host', 'pvm_scalar_host'):
            with self.subTest(suite=target):
                def rejected(arguments, name, **options):
                    suite = arguments[arguments.index('--suite')+1]
                    if suite == target:
                        return dict(exit_code=1, log=target+'-failure.log')
                    return self.suite_result(arguments, name, **options)

                self.checks.command.side_effect = rejected
                with self.assertRaisesRegex(RuntimeError, target+'-failure.log'):
                    ci.qualify_policy(self.checks, self.compiler)

    def test_scalar_codec_zero_exit_cannot_reuse_stale_arc(self):
        """Fresh resident proof cannot excuse an old mixed-codec observation after a green child."""
        for directory in (self.live, self.folder):
            (directory/'pvm_scalar_host.json').write_text(json.dumps(self.proof))

        def omitted(arguments, name, **options):
            suite = arguments[arguments.index('--suite')+1]
            if suite == 'pvm_scalar_host':
                return dict(exit_code=0, log='missing-scalar-arc.log')
            return self.suite_result(arguments, name, **options)

        self.checks.command.side_effect = omitted
        with self.assertRaises(FileNotFoundError) as error:
            ci.qualify_policy(self.checks, self.compiler)
        self.assertIn('pvm_scalar_host.json', str(error.exception))

    def test_state_scalar_support_cannot_change_during_its_run(self):
        """The product fixture's support bytes are checked even though it declares no ARC observation."""
        def changed(arguments, name, **options):
            suite = arguments[arguments.index('--suite')+1]
            if suite == 'pvm_accumulation_scalar_host':
                self.tamper = 'tests/support/pvm_accumulation_program.nim'
            return self.suite_result(arguments, name, **options)

        self.checks.command.side_effect = changed
        with self.assertRaisesRegex(ValueError, 'source changed'):
            ci.qualify_policy(self.checks, self.compiler)

    def test_zero_exit_cannot_hide_arc_growth(self):
        """The shared numeric validator rejects fresh growth even if the child claimed success."""
        self.proof['occupied_after'] += 8
        with self.assertRaisesRegex(ValueError, 'return to baseline'):
            ci.qualify_policy(self.checks, self.compiler)
        self.assertTrue((self.folder/'pvm_fresh_resident.json').exists())

    def test_mapping_header_and_support_contracts_cannot_change(self):
        """Changing an OS binding, helper, oracle or registered profile during execution invalidates its proof."""
        for relative in ('src/pvm/internal/resident_os.h', 'tests/support/arc_evidence.nim',
                'tests/unit/codec/test_pvm_fresh_resident.output',
                'tools/native_requirements/codec/pvm_resident_bytes.json'):
            with self.subTest(source=relative):
                original = (self.root/relative).read_bytes()
                self.tamper = relative
                try:
                    with self.assertRaisesRegex(ValueError, 'source changed'):
                        ci.qualify_policy(self.checks, self.compiler)
                finally:
                    (self.root/relative).write_bytes(original)

    def test_compatibility_profile_cannot_substitute_for_fresh_map(self):
        """The Linux native gate must not silently qualify only a capped managed-storage fallback."""
        for key in ('nimMaxHeap', 'nimHardenOutOfMem', 'useMimalloc', 'useLibc', 'nimNoLibc'):
            for suffix in ('', '=0', '=false'):
                with self.subTest(define=key+suffix):
                    self.profiles['pvm_fresh_resident']['defines'] = ['pvmResidentWitness', key+suffix]
                    with self.assertRaisesRegex(ValueError, 'Resident qualification registration changed'):
                        ci.qualify_policy(self.checks, self.compiler)
                    self.checks.command.assert_not_called()

    def test_resident_witness_is_required(self):
        """Without instrumentation, a passing fallback workload cannot establish mapped acquisitions."""
        self.profiles['pvm_fresh_resident']['defines'] = ['integration']
        with self.assertRaisesRegex(ValueError, 'Resident qualification registration changed'):
            ci.qualify_policy(self.checks, self.compiler)
        self.checks.command.assert_not_called()

    def test_benign_additional_profile_configuration_is_allowed(self):
        """Qualification guards allocation policy without freezing unrelated registered configuration."""
        self.profiles['pvm_fresh_resident']['defines'] = ['integration', 'pvmResidentWitness']
        rows = ci.qualify_policy(self.checks, self.compiler)
        self.assertTrue(any(row['suite'] == 'pvm_fresh_resident' and row['arc'] == self.proof
            for row in rows))

    def test_native_receipt_binds_new_header_and_suite_inputs(self):
        """The performance preflight receives the OS header/support/golden/profile seals in the native receipt."""
        with patch.object(ci, 'BUILD', self.folder), \
                patch.object(ci, 'host_identity', return_value=dict(system='Linux', machine='aarch64', architecture='arm64')), \
                patch.object(ci, 'installed', return_value=(self.compiler, None)), \
                patch.object(ci.subprocess, 'check_output', return_value='a'*40), \
                patch.object(ci, 'qualify_host', return_value=['passed']), \
                patch.object(ci, 'qualify_shared', return_value=dict(status='passed')), \
                patch.object(ci, 'qualify_mixed_arena', return_value=dict(status='passed')), \
                patch.object(ci, 'qualify_read_widths', return_value=dict(status='passed')), \
                patch.object(ci, 'qualify_policy', return_value=['passed']), \
                patch('builtins.print'):
            ci.run()
        observed = json.loads((self.folder/'results.json').read_text())
        self.assertEqual(observed['status'], 'passed')
        for relative in self.inputs:
            self.assertEqual(observed['sources'][relative],
                ci.hashlib.sha256((self.root/relative).read_bytes()).hexdigest())


class SharedQualificationTests(unittest.TestCase):
    """Prove matching common positive/refusal execution is mandatory with inert native tools."""

    def setUp(self):
        """Own tiny source/golden/profile inputs; no compiler or product process is launched."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.profiles = {}
        self.sources = {}
        for directory, suite, defines, golden in (
            ('codec', 'pvm_shared_async_arm',
             ['pvmArm64Jit', 'pvmPaidMixedLoopWitness', 'pvmSharedAsyncWitness'],
             'PVM shared async passed\n'),
            ('codec', 'pvm_shared_async_x86',
             ['pvmX86Jit', 'pvmPaidMixedLoopWitness', 'pvmSharedAsyncWitness'],
             'PVM shared async passed\n'),
            ('state', 'pvm_runtime_policy_refused',
             ['pvmArm64Jit', 'pvmArm64JitRefuse', 'pvmSharedAsyncWitness'],
             'PASS runtime PVM policy\nPVM shared async refusal controls passed\n')):
            source = self.root/'tests/unit'/directory/('test_'+suite+'.nim')
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text('inert main '+suite)
            source.with_suffix('.output').write_text(golden)
            self.sources[suite] = source
            profile = dict(defines=defines, includes=['pvm_jit'], libraries=[], observers=[],
                           prepared=False, directory=directory)
            self.profiles[suite] = profile
            path = self.root/'tools/native_requirements'/directory/(suite+'.json')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(profile))
        helper = self.root/'tests/support/pvm_shared_async.nim'
        helper.parent.mkdir(parents=True)
        helper.write_text('inert shared witness')
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(ci, 'ROOT', self.root))
        self.stack.enter_context(patch.object(ci, 'NATIVE_REQUIREMENTS', self.profiles))
        self.stack.enter_context(patch.object(ci, 'unit_source', side_effect=self.sources.__getitem__))
        self.stack.enter_context(patch.object(ci, 'unit_environment', return_value={}))

    def tools(self, fault=None):
        """Model build/run outcomes from selected mains and exact goldens, preserving failed gates."""
        checks = Mock()
        checks.folder = self.root/'checks'
        builds = []
        binaries = {}

        def build(compiler, source, name, **options):
            """Return an inert file; a failed build cannot reach a target command."""
            builds.append(dict(source=source, defines=options['defines']))
            binary = self.root/name
            binary.write_bytes(b'inert image')
            binaries[str(binary)] = source
            return dict(exit_code=1 if fault == 'build' else 0, log=name+'.log'), binary

        def command(arguments, name, **options):
            """Only the known complete positive or refusal transcript can count as an actual pass."""
            source = binaries[str(arguments[0])]
            output = source.with_suffix('.output').read_text()
            if fault == 'fallback' and 'refused' in name:
                output = 'PASS runtime PVM policy\n'
            elif fault == 'extra':
                output += 'extra output\n'
            elif fault == 'tamper':
                (self.root/'tests/support/pvm_shared_async.nim').write_text('changed source')
            refused = 'refused' in name
            evidence = dict(schema=1, kind='refused' if refused else 'positive',
                isa='x86_64' if 'pvmX86Jit' in builds[-1]['defines'] else 'arm64',
                submitted=1, completed=1, fragments=0 if refused else 1,
                calls=0 if refused else 3, operations=0 if refused else 12288,
                no_retry_checks=3 if refused else 0)
            if fault == 'wrong-kind':
                evidence['kind'] = 'refused' if not refused else 'positive'
            elif fault == 'wrong-isa':
                evidence['isa'] = 'foreign'
            elif fault == 'zero-native':
                evidence['calls'] = 0
            elif fault == 'no-publication':
                evidence['fragments'] = 0
            elif fault == 'no-worker':
                evidence['submitted'] = evidence['completed'] = 0
            elif fault == 'boolean-counter':
                evidence['completed'] = True
            elif fault == 'no-refusal-proof' and refused:
                evidence['no_retry_checks'] = 0
            if fault != 'missing-proof':
                actual_kind = 'refused' if refused else 'positive'
                actual_isa = 'x86_64' if 'pvmX86Jit' in builds[-1]['defines'] else 'arm64'
                path = Path(options['environment']['RAGNAROK_TEST_EVIDENCE'])/(
                    'pvm_shared_'+actual_kind+'_'+actual_isa+'.json')
                path.write_text(json.dumps(evidence))
            return dict(exit_code=1 if fault == 'run' else 0, log=name+'.log', output=output)

        checks.build.side_effect = build
        checks.command.side_effect = command
        return checks, builds

    def test_matching_common_positive_and_real_refusal_on_both_isas(self):
        """x86 must compile its own refusal flags instead of the ARM-only fallback registration."""
        for machine, isa, normal in (('aarch64', 'pvmArm64Jit', 'pvm_shared_async_arm'),
                                    ('x86_64', 'pvmX86Jit', 'pvm_shared_async_x86')):
            with self.subTest(machine=machine):
                # Equivalent declaration order must still reach the matching real-behavior gate.
                self.profiles[normal]['defines'].reverse()
                self.profiles['pvm_runtime_policy_refused']['defines'].reverse()
                checks, builds = self.tools()
                result = ci.qualify_shared(checks, 'compiler', dict(system='Linux', machine=machine))
                self.assertEqual(result['status'], 'passed')
                self.assertEqual([b['source'] for b in builds],
                    [self.sources[normal], self.sources['pvm_runtime_policy_refused']])
                self.assertEqual([set(b['defines']) for b in builds],
                    [{isa, 'pvmPaidMixedLoopWitness', 'pvmSharedAsyncWitness'},
                     {isa, isa+'Refuse', 'pvmSharedAsyncWitness'}])
                self.assertEqual(result['production_defines'], [isa])
                self.assertEqual(set(result['controls'][1]['registered_defines']),
                    {'pvmArm64Jit', 'pvmArm64JitRefuse', 'pvmSharedAsyncWitness'})
                self.assertEqual(checks.command.call_count, 2)
                self.assertEqual(len(result['sources']), 10)

    def test_failed_build_run_fallback_or_golden_cannot_pass(self):
        """A fallback-only second line omission or unrelated output is not native nil-refusal proof."""
        for fault in ('build', 'run', 'fallback', 'extra'):
            with self.subTest(fault=fault):
                checks, _ = self.tools(fault)
                with self.assertRaises(RuntimeError):
                    ci.qualify_shared(checks, 'compiler', dict(system='Linux', machine='x86_64'))
                self.assertLessEqual(checks.command.call_count, 2)
                if fault == 'build':
                    checks.command.assert_not_called()

    def test_golden_without_real_supported_evidence_never_qualifies(self):
        """A stale proof or unsupported exact-golden pass cannot replace actual native behavior."""
        for fault in ('missing-proof', 'wrong-kind', 'wrong-isa', 'zero-native',
                      'boolean-counter', 'no-refusal-proof', 'no-publication', 'no-worker'):
            with self.subTest(fault=fault):
                checks, _ = self.tools(fault)
                directory = checks.folder/'shared-pvm_shared_async_x86-evidence'
                directory.mkdir(parents=True, exist_ok=True)
                # Clearing before execution must defeat a previous valid native receipt as well.
                stale = directory/'pvm_shared_positive_x86_64.json'
                stale.write_text(json.dumps(dict(schema=1, kind='positive', isa='x86_64',
                    submitted=1, completed=1, fragments=1, calls=3, operations=12288,
                    no_retry_checks=0)))
                with self.assertRaises((OSError, ValueError)):
                    ci.qualify_shared(checks, 'compiler', dict(system='Linux', machine='x86_64'))

    def test_source_mutation_or_foreign_witness_profile_refuses(self):
        """The source-bound receipt cannot survive changed inputs or a mismatched positive ISA."""
        self.profiles['pvm_shared_async_x86']['defines'] = [
            'pvmArm64Jit', 'pvmPaidMixedLoopWitness', 'pvmSharedAsyncWitness']
        checks, _ = self.tools()
        with self.assertRaisesRegex(ValueError, 'registration'):
            ci.qualify_shared(checks, 'compiler', dict(system='Linux', machine='x86_64'))
        checks.build.assert_not_called()
        self.profiles['pvm_shared_async_x86']['defines'] = [
            'pvmX86Jit', 'pvmPaidMixedLoopWitness', 'pvmSharedAsyncWitness', 'pvmSharedAsyncWitness']
        with self.assertRaisesRegex(ValueError, 'registration'):
            ci.qualify_shared(checks, 'compiler', dict(system='Linux', machine='x86_64'))
        checks.build.assert_not_called()
        self.profiles['pvm_shared_async_x86']['defines'] = [
            'pvmX86Jit', 'pvmPaidMixedLoopWitness', 'pvmSharedAsyncWitness']
        checks, _ = self.tools('tamper')
        with self.assertRaisesRegex(ValueError, 'source changed'):
            ci.qualify_shared(checks, 'compiler', dict(system='Linux', machine='x86_64'))

    def test_paid_continuation_coverage_cannot_be_omitted(self):
        """A positive native gate must not silently drop the committed-prefix repair cases."""
        self.profiles['pvm_shared_async_x86']['defines'].remove('pvmPaidMixedLoopWitness')
        checks, _ = self.tools()
        with self.assertRaisesRegex(ValueError, 'registration'):
            ci.qualify_shared(checks, 'compiler', dict(system='Linux', machine='x86_64'))
        checks.build.assert_not_called()

    def test_unavailable_host_does_not_claim_common_native_pass(self):
        """Unsupported hosts preserve truthful fallback without starting a common native target."""
        checks, _ = self.tools()
        result = ci.qualify_shared(checks, 'compiler', dict(system='Darwin', machine='x86_64'))
        self.assertEqual(result['status'], 'unavailable')
        checks.build.assert_not_called()
        checks.command.assert_not_called()

    def test_common_failure_prevents_overall_green_receipt(self):
        """Even green legacy gates cannot publish native CI success when common proof fails."""
        # This isolated shared-gate fixture supplies shared sources; resident provenance has its own test.
        compiler = self.root/'tool/bin/nimony'
        compiler.parent.mkdir(parents=True)
        compiler.write_bytes(b'inert compiler')
        (compiler.parent.parent/'NIGHTLY.txt').write_text('inert pinned identity')
        with patch.object(ci, 'BUILD', self.root/'results'), \
                patch.object(ci, 'host_identity', return_value=dict(system='Linux',
                    machine='x86_64', architecture='x86_64')), \
                patch.object(ci, 'installed', return_value=(compiler, None)), \
                patch.object(ci.subprocess, 'check_output', return_value='a'*40), \
                patch.object(ci, 'qualify_host', return_value=['legacy passed']), \
                patch.object(ci, 'resident_source_paths', return_value=[]), \
                patch.object(ci, 'scalar_source_paths', return_value=[]), \
                patch.object(ci, 'qualify_shared', side_effect=RuntimeError('common failed')), \
                patch.object(ci, 'qualify_policy') as policies:
            with self.assertRaisesRegex(RuntimeError, 'common failed'):
                ci.run()
            result = json.loads((self.root/'results/results.json').read_text())
            self.assertEqual(result['status'], 'incomplete')
            self.assertIn('common failed', result['error'])
            self.assertIn('tests/support/pvm_shared_async.nim', result['sources'])
            policies.assert_not_called()

    def test_unavailable_common_receipt_cannot_green_a_supported_host(self):
        """An unsupported common result is not a native pass, even when legacy checks are green."""
        # Keep this existing host/shared verdict test independent of the separately tested resident inputs.
        compiler = self.root/'tool/bin/nimony'
        compiler.parent.mkdir(parents=True)
        compiler.write_bytes(b'inert compiler')
        (compiler.parent.parent/'NIGHTLY.txt').write_text('inert pinned identity')
        with patch.object(ci, 'BUILD', self.root/'results'), \
                patch.object(ci, 'host_identity', return_value=dict(system='Linux',
                    machine='x86_64', architecture='x86_64')), \
                patch.object(ci, 'installed', return_value=(compiler, None)), \
                patch.object(ci.subprocess, 'check_output', return_value='a'*40), \
                patch.object(ci, 'qualify_host', return_value=['legacy passed']), \
                patch.object(ci, 'resident_source_paths', return_value=[]), \
                patch.object(ci, 'scalar_source_paths', return_value=[]), \
                patch.object(ci, 'qualify_shared', return_value=dict(status='unavailable')), \
                patch.object(ci, 'qualify_policy') as policies:
            with self.assertRaisesRegex(RuntimeError, 'matching shared'):
                ci.run()
            self.assertEqual(json.loads((self.root/'results/results.json').read_text())['status'],
                             'incomplete')
            policies.assert_not_called()

    def test_selected_shared_refusal_replaces_duplicate_fallback_check(self):
        """The real refused main already keeps the unbound checks; unsupported hosts retain fallback."""
        checks = Mock()
        checks.command.return_value = dict(exit_code=0, log='policy.log')
        with patch.object(ci, 'RESIDENT_SUITES', ()), \
                patch.object(ci, 'SCALAR_SUITES', ()), \
                patch.object(ci, 'resident_source_paths', return_value=[]), \
                patch.object(ci, 'scalar_source_paths', return_value=[]):
            rows = ci.qualify_policy(checks, Path('inert-compiler'), shared_refusal=True)
        self.assertEqual([row['suite'] for row in rows], ['pvm_memory_reuse', 'pvm_runtime_policy'])


class QualificationTests(unittest.TestCase):
    def witness_receipt(self, native, *, refused=False, macro_refused=False,
                        resident_refused=False,
                        region='ARM_SELF_REGION_CASES,1920\n'):
        """Model raw native mode controls separately from unbound checked frame cohorts."""
        counts = (64896, 507, 24843) if native else (0, 0, 0)
        assert not (native and refused)
        assert not macro_refused or native
        assert not resident_refused or native
        assert not (macro_refused and resident_refused)
        backend_active = native and not macro_refused
        macro_active = False
        macro_resident = False
        macro_backend = 31 if backend_active else 3 if native or refused else 0
        macro_frame = 13524 if native or refused else 0
        image_words = 0
        return 'TRANSFER_STATS,0,0\n' + (
            f'ARM_SHIFT_PAIR_LITERAL_CASES,{counts[0]}\n'
            f'ARM_SHIFT_PAIR_DECLINE_CASES,{counts[1]}\n'
            f'ARM_LOAD_WIDTH_LITERAL_CASES,{counts[2]}\n'
            f'ARM_DIRECT_BRANCH_LITERAL_CASES,{1640 if native else 0}\n'
            'ARM_DIRECT_BRANCH_CONTROL_CASES,122\n'
            'ARM_STORE_FALLBACK_CONTROL_CASES,43904\n'
            'ARM_DIRTY_LOOP_LIVE_IN_CASES,156\n'
            'BOUNDED_CONTINUATION_LONG_CASES,120\n'
            'BOUNDED_MIXED_CONTINUATION_LONG_CASES,120\n'
            'BOUNDED_NATIVE_FALLBACK_LONG_CASES,120\n'
            'ARM_PREFIX_READ_FRAME_CASES,662\n'
            'ARM_PREFIX_READ_SOURCE_BOUNDARY_CASES,177\n'
            'ARM_PREFIX_READ_CHARGE_BOUNDARY_CASES,106\n'
            'ARM_PREFIX_READ_NATIVE_ACTIVATIONS,0\n'
            'ARM_PREFIX_READ_NATIVE_REFUSALS,0\n'
            f'ARM_PREFIX_READ_LITERAL_ROLLBACKS,{4 if native else 0}\n'
            'ARM_PREFIX_READ_OVERSIZE_FALLBACK_CASES,1\n'
            f'ARM_PREFIX_READ_NEAR_CAP_LITERAL,{1 if native else 0}\n'
            f'ARM_MEMORY_CYCLE_FRAME_CASES,{7236 if native or refused else 0}\n'
            f'ARM_MEMORY_CYCLE_BACKEND_CASES,{19 if native else 1 if refused else 0}\n'
            f'ARM_RESIDENT_MEMORY_CYCLE_FRAME_CASES,{12328 if native or refused else 0}\n'
            f'ARM_RESIDENT_MEMORY_CYCLE_BACKEND_CASES,{47 if native else 3 if refused else 0}\n'
            f'ARM_MACRO_BACKEND_CASES,{macro_backend}\n'
            f'ARM_MACRO_FRAME_CASES,{macro_frame}\n'
            f'ARM_MACRO_ACTIVE,{int(macro_active)}\n'
            f'ARM_MACRO_LATE_READ_REFUND,{int(macro_active)}\n'
            f'ARM_MACRO_SIGNED_BACKEDGE,{int(macro_active)}\n'
            f'ARM_MACRO_OWNER_MOVE,{int(macro_active)}\n'
            f'ARM_MACRO_CHECKED_REENTRY_CASES,{162 if native else 0}\n'
            f'ARM_MACRO_RESIDENT,{int(macro_resident)}\n'
            f'ARM_MACRO_ROLLBACK_ALIAS,{int(macro_active)}\n'
            f'ARM_MACRO_IMAGE_WORDS,{image_words}\n' +
            ('ARM_CLIPPED_FRAME_BOUNDARY,4,0,0,0,0,0,0,0,0\n' if native or refused else '') +
            'ARM_CHECKED_STORE_SECOND_EXIT_CASES,360\n' + region +
            'ARM_DIRTY_LOOP_CONTROL_CASES,840\n'
            'ARM_DIRTY_LOOP_ALIAS_REFUSAL,1\n' +
            ('ARM_DIRTY_LOOP_OWNER,1\nARM_WORD_OWNER,1\nARM_WORD_CONTROL_CASES,698\nARM_WORD_ALIAS_CASES,110\n' if native or refused else '') +
            ('ARM_WORD_GROUPS,0\nARM_DIRTY_LOOP,0,0,0\n' if native else
             'ARM_WORD_GROUPS,0\n' if refused else '') +
            ('ARM_REGION_SCALAR_MATCH_CASES,111\n'
             'CLIPPED_ISA_SPAN_WORDS,36,31\n'
             'CLIPPED_ISA_LEAF_WORDS,34,29\n'
             'CLIPPED_INTERVAL_NATIVE_CASES,288\n'
             'CLIPPED_WIDTH_NATIVE_CASES,378\n'
             'CLIPPED_DIRECT_NATIVE_CASES,28\n'
             'CLIPPED_WRAP_NATIVE_CASES,12\n'
             'CLIPPED_ROLLBACK_NATIVE_CASES,3\n'
             'ARM_CLIPPED_NATIVE_CASES,709\n' if native else ''))

    def check(self, native, receipt=None, build_error=False, region_receipt=None,
              refused_receipt=None, macro_refused_receipt=None, resident_refused_receipt=None,
              legacy_receipt=None, legacy_exit_code=1):
        """Model tool process boundaries; all native assertions stay in the maintained Nim/C witnesses."""
        ordinary = self.witness_receipt(native)
        refused = self.witness_receipt(False, refused=True)
        macro_refused = self.witness_receipt(True, macro_refused=True)
        resident_refused = self.witness_receipt(True, resident_refused=True)
        class Checks:
            folder=Path('/tmp/pvm-ci-test')
            def __init__(self):
                self.builds=[]
            def build(self, compiler, source, name, **kwargs):
                self.builds.append((name,kwargs['defines']))
                if name.endswith('-copy'):
                    return dict(exit_code=1,output="'=dup' is not available for type <Flat"),self.folder/name
                return dict(exit_code=int(build_error),output='compiler failure' if build_error else ''),self.folder/name
            def command(self, args, name):
                output=''
                if name=='memory-run':
                    output=('ARM_MEMORY_OK,1000,capacity,publication,retirement,integer64\n' if native
                            else 'ARM_MEMORY_UNAVAILABLE,checked-fallback\n')
                elif name=='witness-run':
                    output=receipt if receipt is not None else ordinary
                elif name=='witness-legacy-abi-refused-run':
                    output=(legacy_receipt if legacy_receipt is not None else
                            'ARM_CLIPPED_ABI_POSITIVE,1,1\n[Assertion Failure] \n')
                    return dict(exit_code=legacy_exit_code,output=output)
                elif name=='witness-refused-run':
                    output=refused_receipt if refused_receipt is not None else refused
                elif name=='witness-macro-refused-run':
                    output=macro_refused_receipt if macro_refused_receipt is not None else macro_refused
                elif name=='witness-resident-refused-run':
                    output=(resident_refused_receipt if resident_refused_receipt is not None
                            else resident_refused)
                elif name.startswith('region-refusal'):
                    output='ARM_REGION_LOCAL_SHAPES,true\n'+''.join(
                        'ARM_REGION_REFUSAL_FRAME,'+order+',0,0,0,0\n'
                        for order in ('0,0','0,1','1,1'))
                    if name=='region-refusal-run' and region_receipt is not None:
                        output=region_receipt
                elif '-move-run' in name:
                    output='0\n0\n'
                return dict(exit_code=0,output=output)
        checks=Checks()
        return qualify(checks,Path('/compiler'),native=native),checks.builds

    def macro_mode_receipt(self, mode):
        """Supply independent complete transcripts for each native and checked-only policy."""
        return {
            'native': self.witness_receipt(True),
            'resident-refused': self.witness_receipt(True, resident_refused=True),
            'native-refused': self.witness_receipt(False, refused=True),
            'macro-refused': self.witness_receipt(True, macro_refused=True),
            'interpreted': self.witness_receipt(False),
        }[mode]

    def check_macro_mode(self, mode, receipt):
        """Route one damaged transcript through its real full-qualification witness process."""
        if mode == 'resident-refused':
            return self.check(True, resident_refused_receipt=receipt)
        if mode == 'native-refused':
            return self.check(True, refused_receipt=receipt)
        if mode == 'macro-refused':
            return self.check(True, macro_refused_receipt=receipt)
        return self.check(mode == 'native', receipt=receipt)

    def test_native_and_unavailable_profiles(self):
        """The explicit ARM-only helper retains off-platform fallback controls independently of x86 qualification."""
        for native in (True,False):
            rows,builds=self.check(native)
            self.assertEqual(len(rows),14 if native else 11)
            witness_index=2 if native else 1  # Native qualification first exercises legacy ABI refusal.
            self.assertIsNone(rows[witness_index]['dirty_loop'])
            self.assertIsNone(rows[witness_index+1]['dirty_loop'])
            witness=next(flags for name,flags in builds if name=='witness')
            self.assertEqual(witness,['pvmArm64Jit','pvmArmMacroReceipt',
                                      'pvmArmDirtyLoopOwnerReceipt'] if native else [])
            refused=next(flags for name,flags in builds if name=='witness-refused')
            self.assertIn('pvmArm64JitRefuse',refused)
            self.assertIn('pvmArmDirtyLoopOwnerReceipt',refused)
            legacy=[flags for name,flags in builds if name=='witness-legacy-abi-refused']
            self.assertEqual(legacy, [['pvmArm64Jit','pvmArmClippedLegacyAbiRefuse']] if native else [])
            resident=[flags for name,flags in builds if name=='witness-resident-refused']
            if native:
                self.assertEqual(resident, [['pvmArm64Jit','pvmArmMacroResidentRefuse',
                                             'pvmArmMacroReceipt','pvmArmDirtyLoopOwnerReceipt']])
            else:
                self.assertEqual(resident, [])

    def test_legacy_context_abi_refusal_requires_one_positive_control(self):
        """The intentionally failing process must first prove both valid bridge profiles ran."""
        valid='ARM_CLIPPED_ABI_POSITIVE,1,1\n[Assertion Failure] \n'
        for transcript in ('[Assertion Failure] \n',
                           'ARM_CLIPPED_ABI_POSITIVE,1\n[Assertion Failure] \n',
                           'ARM_CLIPPED_ABI_POSITIVE,1,1\n'+valid,
                           'ARM_CLIPPED_ABI_POSITIVE,1,1\n',
                           valid+'ARM_CLIPPED_ABI_REJECTION_MISSING\n'):
            with self.subTest(transcript=transcript), self.assertRaisesRegex(
                    ValueError, 'typed ARM context ABI rejection'):
                self.check(True,legacy_receipt=transcript)
        with self.assertRaisesRegex(ValueError, 'typed ARM context ABI rejection'):
            self.check(True,legacy_receipt=valid,legacy_exit_code=0)

    def test_clipped_receipts_are_complete_in_each_native_mode(self):
        """Every native-capable mode must supply one exact clipped witness transcript."""
        markers=('CLIPPED_ISA_SPAN_WORDS', 'CLIPPED_ISA_LEAF_WORDS',
                 'CLIPPED_INTERVAL_NATIVE_CASES', 'CLIPPED_WIDTH_NATIVE_CASES',
                 'CLIPPED_DIRECT_NATIVE_CASES', 'CLIPPED_WRAP_NATIVE_CASES',
                 'CLIPPED_ROLLBACK_NATIVE_CASES', 'ARM_CLIPPED_NATIVE_CASES')
        for mode in ('native','macro-refused','resident-refused'):
            complete=self.macro_mode_receipt(mode)
            for marker in markers:
                line,=[row+'\n' for row in complete.splitlines() if row.startswith(marker+',')]
                for replacement in ('',marker+',\n',line+line):
                    damaged=complete.replace(line,replacement,1)
                    with self.subTest(mode=mode,marker=marker,replacement=replacement), \
                            self.assertRaisesRegex(ValueError,'native clipped-read receipt: '+marker):
                        self.check_macro_mode(mode,damaged)
        for mode in ('native-refused','interpreted'):
            complete=self.macro_mode_receipt(mode)
            for marker in markers:
                with self.subTest(mode=mode,marker=marker), self.assertRaisesRegex(
                        ValueError,'native clipped-read receipt: '+marker):
                    self.check_macro_mode(mode,complete+marker+',1\n')

    def test_clipped_frame_boundary_receipt_is_mode_specific(self):
        """All compiled ARM frame cohorts remain complete and reject fabricated native entries."""
        marker='ARM_CLIPPED_FRAME_BOUNDARY,'
        for mode in ('native','macro-refused','resident-refused','native-refused'):
            complete=self.macro_mode_receipt(mode)
            line,=[row+'\n' for row in complete.splitlines() if row.startswith(marker)]
            for replacement,reason in (('', 'frame-owned clipped-boundary'),
                                       (marker+'4,0,0,0,0,0,0,0\n', 'frame-owned clipped-boundary'),
                                       (line+line, 'frame-owned clipped-boundary'),
                                       (marker+'4,0,0,0,0,0,no,0,0\n', 'Malformed frame-owned'),
                                       (marker+'4,1,0,0,0,0,0,0,0\n', 'Unbound clipped frame')):
                with self.subTest(mode=mode,replacement=replacement), self.assertRaisesRegex(
                        ValueError,reason):
                    self.check_macro_mode(mode,complete.replace(line,replacement,1))
        with self.assertRaisesRegex(ValueError,'Refused or interpreted frame claimed native'):
            self.check_macro_mode('interpreted',self.macro_mode_receipt('interpreted')+
                marker+'4,0,0,0,0,0,0,0,0\n')

    def test_macro_controls_are_required_through_full_qualification(self):
        """Each mode keeps all unrelated gates valid while one macro proof is damaged."""
        markers = ('ARM_MACRO_BACKEND_CASES', 'ARM_MACRO_FRAME_CASES',
                   'ARM_MACRO_ACTIVE', 'ARM_MACRO_LATE_READ_REFUND',
                   'ARM_MACRO_SIGNED_BACKEDGE', 'ARM_MACRO_OWNER_MOVE',
                   'ARM_MACRO_CHECKED_REENTRY_CASES', 'ARM_MACRO_RESIDENT',
                   'ARM_MACRO_ROLLBACK_ALIAS', 'ARM_MACRO_IMAGE_WORDS')
        for mode in ('native', 'resident-refused', 'native-refused', 'macro-refused', 'interpreted'):
            complete = self.witness_receipt(mode in ('native', 'resident-refused', 'macro-refused'),
                refused=mode=='native-refused', macro_refused=mode=='macro-refused',
                resident_refused=mode=='resident-refused')
            for marker in markers:
                line, = [row+'\n' for row in complete.splitlines()
                         if row.startswith(marker+',')]
                for kind, replacement in (('missing', ''), ('truncated', marker+',\n'),
                                          ('duplicate', line+line)):
                    damaged = complete.replace(line, replacement)
                    arguments = ({'refused_receipt': damaged} if mode=='native-refused'
                                 else {'macro_refused_receipt': damaged} if mode=='macro-refused'
                                 else {'resident_refused_receipt': damaged} if mode=='resident-refused'
                                 else {'receipt': damaged})
                    with self.subTest(mode=mode, marker=marker, kind=kind), \
                            self.assertRaisesRegex(ValueError, 'ARM macro witness: '+marker):
                        self.check(mode!='interpreted', **arguments)

    def test_macro_mode_receipts_cannot_cross_full_qualification(self):
        """Swap only macro proof fields so unrelated gates cannot mask a policy mismatch."""
        markers = ('ARM_MACRO_BACKEND_CASES', 'ARM_MACRO_FRAME_CASES',
                   'ARM_MACRO_ACTIVE', 'ARM_MACRO_LATE_READ_REFUND',
                   'ARM_MACRO_SIGNED_BACKEDGE', 'ARM_MACRO_OWNER_MOVE',
                   'ARM_MACRO_CHECKED_REENTRY_CASES', 'ARM_MACRO_RESIDENT',
                   'ARM_MACRO_ROLLBACK_ALIAS', 'ARM_MACRO_IMAGE_WORDS')
        modes = ('native', 'resident-refused', 'native-refused', 'macro-refused', 'interpreted')
        for expected in modes:
            original = self.macro_mode_receipt(expected)
            for actual in modes:
                if actual == expected:
                    continue
                donor = self.macro_mode_receipt(actual)
                changed = original
                for marker in markers:
                    old, = [line+'\n' for line in original.splitlines()
                            if line.startswith(marker+',')]
                    new, = [line+'\n' for line in donor.splitlines()
                            if line.startswith(marker+',')]
                    changed = changed.replace(old, new, 1)
                with self.subTest(expected=expected, actual=actual):
                    if changed == original:
                        # Raw build/source controls distinguish policy where receipts actually differ.
                        self.check_macro_mode(expected, changed)
                    else:
                        with self.assertRaisesRegex(ValueError, 'ARM macro witness:'):
                            self.check_macro_mode(expected, changed)

    def test_unbound_macro_image_claims_rejected_full_qualification(self):
        """Real raw bounded images do not permit a bare frame to claim native publication."""
        modes = ('native', 'resident-refused', 'native-refused', 'macro-refused', 'interpreted')
        for mode in modes:
            original = self.macro_mode_receipt(mode)
            self.check_macro_mode(mode, original)
            line, = [row+'\n' for row in original.splitlines()
                     if row.startswith('ARM_MACRO_IMAGE_WORDS,')]
            for words in (1, 1024, 1025, 'not-decimal'):
                with self.subTest(mode=mode, invalid=words), self.assertRaisesRegex(
                        ValueError, 'ARM macro witness: ARM_MACRO_IMAGE_WORDS'):
                    self.check_macro_mode(mode, original.replace(
                        line, f'ARM_MACRO_IMAGE_WORDS,{words}\n', 1))

    def test_candidate_local_checked_receipts_are_mandatory(self):
        """Full checked ownership orders and preceding raw shape controls remain mandatory."""
        shapes='ARM_REGION_LOCAL_SHAPES,true\n'
        zero=''.join('ARM_REGION_REFUSAL_FRAME,'+order+',0,0,0,0\n'
                     for order in ('0,0','0,1','1,1'))
        reordered=''.join('ARM_REGION_REFUSAL_FRAME,'+order+',0,0,0,0\n'
                          for order in ('1,1','0,1','0,0'))
        self.check(True,region_receipt=shapes+zero)
        for raw,reason in (('', 'candidate-local'), (shapes+reordered, 'candidate-local'),
                           (shapes+zero+zero, 'candidate-local'),
                           (shapes+zero.replace('0,0,0,0\n','0,1,2,1\n'), 'claimed native'),
                           (zero, 'direct ARM')):
            with self.subTest(receipt=raw), self.assertRaisesRegex(ValueError,reason):
                self.check(True,region_receipt=raw)

    def test_fabricated_frame_execution_and_compiler_failure(self):
        """Missing/duplicate/fabricated frame transfer counters and failed compilation cannot qualify."""
        for receipt in ('','TRANSFER_STATS,1,2\n','TRANSFER_STATS,0,0\nTRANSFER_STATS,0,0\n'):
            with self.subTest(receipt=receipt),self.assertRaisesRegex(ValueError,'frame transfer'):
                complete = self.witness_receipt(True).replace('TRANSFER_STATS,0,0\n',receipt)
                self.check(True,complete)
        with self.assertRaisesRegex(RuntimeError,'compiler failure'):
            self.check(True,build_error=True)


    def test_complete_single_block_receipt_is_required(self):
        """A valid checked transfer cannot disguise absent, incomplete or repeated source coverage."""
        for marker in ('', 'ARM_SELF_REGION_CASES,1919\n',
                       'ARM_SELF_REGION_CASES,1920\nARM_SELF_REGION_CASES,1920\n'):
            with self.subTest(marker=marker),self.assertRaisesRegex(ValueError,'one-block'):
                self.check(True,self.witness_receipt(True,region=marker))


    def test_required_controls_are_independently_checked(self):
        """Each new control must fail for its own missing/incomplete marker after all other gates pass."""
        controls = (
            ('ARM_SHIFT_PAIR_LITERAL_CASES',64896,'paired-shift'),
            ('ARM_SHIFT_PAIR_DECLINE_CASES',507,'paired-shift'),
            ('ARM_LOAD_WIDTH_LITERAL_CASES',24843,'guarded-load width'),
            ('ARM_STORE_FALLBACK_CONTROL_CASES',43904,'checked-store source'),
            ('ARM_DIRTY_LOOP_LIVE_IN_CASES',156,'store-only register'),
            ('ARM_MEMORY_CYCLE_FRAME_CASES',7236,'memory-cycle frame'),
            ('ARM_MEMORY_CYCLE_BACKEND_CASES',19,'memory-cycle backend'),
            ('ARM_RESIDENT_MEMORY_CYCLE_FRAME_CASES',12328,'resident memory-cycle frame'),
            ('ARM_RESIDENT_MEMORY_CYCLE_BACKEND_CASES',47,'resident memory-cycle backend'),
            ('ARM_CHECKED_STORE_SECOND_EXIT_CASES',360,'checked-store exit'),
            ('ARM_DIRTY_LOOP_CONTROL_CASES',840,'ARM_DIRTY_LOOP_CONTROL_CASES'),
            ('ARM_DIRTY_LOOP_ALIAS_REFUSAL',1,'ARM_DIRTY_LOOP_ALIAS_REFUSAL'),
            ('ARM_DIRTY_LOOP_OWNER',1,'ARM_DIRTY_LOOP_OWNER'),
            ('ARM_WORD_OWNER',1,'ARM_WORD_OWNER'),
            ('ARM_WORD_CONTROL_CASES',698,'ARM_WORD_CONTROL_CASES'),
            ('ARM_WORD_ALIAS_CASES',110,'ARM_WORD_ALIAS_CASES'),
            ('ARM_REGION_SCALAR_MATCH_CASES',111,'scalar region-charge'),
            ('ARM_DIRECT_BRANCH_LITERAL_CASES',1640,'direct-read witness'),
            ('ARM_DIRECT_BRANCH_CONTROL_CASES',122,'direct-read witness'),
        )
        complete = self.witness_receipt(True)
        # Keep every unrelated gate valid so a mutation must reach the selected diagnostic.
        for marker,count,reason in controls:
            line = f'{marker},{count}\n'
            # Both absent coverage and a truncated witness must fail independently.
            for replacement in ('',f'{marker},{count-1}\n'):
                with self.subTest(marker=marker,replacement=replacement),self.assertRaisesRegex(ValueError,reason):
                    self.check(True,complete.replace(line,replacement))

    def test_memory_cycle_controls_are_required_in_every_mode(self):
        """No native, forced-refusal or unavailable run can hide missing or duplicated cycle coverage."""
        for native, refused in ((True, False), (False, True), (False, False)):
            complete = self.witness_receipt(native, refused=refused)
            counts = [('FRAME', 7236 if native or refused else 0),
                      ('BACKEND', 19 if native else 1 if refused else 0)]
            for kind, count in counts:
                marker = f'ARM_MEMORY_CYCLE_{kind}_CASES,{count}\n'
                for replacement in ('', f'ARM_MEMORY_CYCLE_{kind}_CASES,{count-1}\n', marker+marker):
                    # Keep every unrelated receipt valid to isolate the intended rejection.
                    damaged = complete.replace(marker, replacement)
                    with self.subTest(native=native, refused=refused, kind=kind, replacement=replacement), \
                            self.assertRaisesRegex(ValueError, 'memory-cycle '+kind.lower()):
                        if refused:
                            self.check(True, refused_receipt=damaged)
                        else:
                            self.check(native, receipt=damaged)

    def test_resident_cycle_controls_are_required_in_every_mode(self):
        """Residency cannot pass on missing, partial or duplicate kernel/frame execution coverage."""
        for native, refused in ((True, False), (False, True), (False, False)):
            complete = self.witness_receipt(native, refused=refused)
            counts = [('FRAME', 12328 if native or refused else 0),
                      ('BACKEND', 47 if native else 3 if refused else 0)]
            for kind, count in counts:
                marker = f'ARM_RESIDENT_MEMORY_CYCLE_{kind}_CASES,{count}\n'
                for replacement in ('', f'ARM_RESIDENT_MEMORY_CYCLE_{kind}_CASES,{count-1}\n', marker+marker):
                    damaged = complete.replace(marker, replacement)
                    with self.subTest(native=native, refused=refused, kind=kind, replacement=replacement), \
                            self.assertRaisesRegex(ValueError, 'resident memory-cycle '+kind.lower()):
                        if refused:
                            self.check(True, refused_receipt=damaged)
                        else:
                            self.check(native, receipt=damaged)

    def test_bounded_continuations_are_required_in_every_mode(self):
        """Missing, partial or duplicate long-block coverage cannot qualify any continuation shape."""
        for native, refused in ((True, False), (False, True), (False, False)):
            complete = self.witness_receipt(native, refused=refused)
            for marker, shape in (('BOUNDED_CONTINUATION_LONG_CASES', 'fused'),
                                  ('BOUNDED_MIXED_CONTINUATION_LONG_CASES', 'non-fused'),
                                  ('BOUNDED_NATIVE_FALLBACK_LONG_CASES', 'native fallback')):
                line = marker+',120\n'
                for replacement in ('', marker+',119\n', line+line):
                    damaged = complete.replace(line, replacement)
                    with self.subTest(native=native, refused=refused, shape=shape, replacement=replacement), \
                            self.assertRaisesRegex(ValueError, 'bounded continuation '+shape):
                        if refused:
                            self.check(True, refused_receipt=damaged)
                        else:
                            self.check(native, receipt=damaged)

    def test_prefix_read_controls_are_required_in_every_mode(self):
        """Real execution, rollback and source/capacity boundaries cannot disappear behind a green transcript."""
        for native, refused in ((True, False), (False, True), (False, False)):
            complete = self.witness_receipt(native, refused=refused)
            controls = (
                ('ARM_PREFIX_READ_FRAME_CASES', 662, 'frame'),
                ('ARM_PREFIX_READ_SOURCE_BOUNDARY_CASES', 177, 'source boundary'),
                ('ARM_PREFIX_READ_CHARGE_BOUNDARY_CASES', 106, 'charge boundary'),
                ('ARM_PREFIX_READ_NATIVE_ACTIVATIONS', 0, 'checked frame activation absence'),
                ('ARM_PREFIX_READ_NATIVE_REFUSALS', 0, 'checked frame refusal absence'),
                ('ARM_PREFIX_READ_LITERAL_ROLLBACKS', 4 if native else 0, 'literal rollback'),
                ('ARM_PREFIX_READ_OVERSIZE_FALLBACK_CASES', 1, 'oversize fallback'),
                ('ARM_PREFIX_READ_NEAR_CAP_LITERAL', 1 if native else 0, 'near capacity'))
            for marker, count, kind in controls:
                line = marker+','+str(count)+'\n'
                for replacement in ('', marker+','+str(count-1)+'\n', line+line):
                    damaged = complete.replace(line, replacement)
                    with self.subTest(native=native, refused=refused, kind=kind, replacement=replacement), \
                            self.assertRaisesRegex(ValueError, 'prefix-read '+kind):
                        if refused:
                            self.check(True, refused_receipt=damaged)
                        else:
                            self.check(native, receipt=damaged)

    def test_store_only_controls_are_required_in_fallback_modes(self):
        """Unavailable hosts and explicit OS refusal still need complete store-only input coverage."""
        marker = 'ARM_DIRTY_LOOP_LIVE_IN_CASES,156\n'
        for refused in (False, True):
            complete = self.witness_receipt(False, refused=refused)
            for replacement in ('', 'ARM_DIRTY_LOOP_LIVE_IN_CASES,155\n'):
                # Keep the native/ownership counters valid for this mode so only absent coverage rejects.
                damaged = complete.replace(marker, replacement)
                with self.subTest(refused=refused, replacement=replacement), \
                        self.assertRaisesRegex(ValueError, 'store-only register'):
                    if refused:
                        self.check(True, refused_receipt=damaged)
                    else:
                        self.check(False, receipt=damaged)

    def test_dirty_loop_receipts_are_mode_specific(self):
        """Complete checked owners stay mandatory; invented dirty-loop activity is rejected."""
        complete = self.witness_receipt(True)
        loop = 'ARM_DIRTY_LOOP,0,0,0\n'
        for replacement, reason in (
            ('', 'call/block/decline'),
            ('ARM_DIRTY_LOOP,2,2,1\n', 'claimed native dirty-loop'),
            ('ARM_DIRTY_LOOP,2,16,0\n', 'claimed native dirty-loop'),
            (loop + loop, 'call/block/decline'),
        ):
            with self.subTest(replacement=replacement), self.assertRaisesRegex(ValueError, reason):
                self.check(True, complete.replace(loop, replacement))
        refused = self.witness_receipt(False, refused=True)
        with self.assertRaisesRegex(ValueError, 'ARM_DIRTY_LOOP_OWNER'):
            self.check(True, refused_receipt=refused.replace('ARM_DIRTY_LOOP_OWNER,1\n', ''))
        with self.assertRaisesRegex(ValueError, 'entered dirty-loop code'):
            self.check(True, refused_receipt=refused + loop)
        with self.assertRaisesRegex(ValueError, 'ARM_DIRTY_LOOP_OWNER'):
            self.check(False, receipt=self.witness_receipt(False) + 'ARM_DIRTY_LOOP_OWNER,1\n')

    def test_native_word_group_and_refusal_receipts(self):
        """Missing group receipts and fabricated native groups must fail qualification."""
        complete = self.witness_receipt(True)
        group = 'ARM_WORD_GROUPS,0\n'
        for replacement in ('', 'ARM_WORD_GROUPS,5\n', 'ARM_WORD_GROUPS,0\nARM_WORD_GROUPS,0\n'):
            with self.subTest(replacement=replacement), self.assertRaisesRegex(ValueError,'word-group'):
                self.check(True,complete.replace(group,replacement))
        refused = self.witness_receipt(False, refused=True)
        with self.assertRaisesRegex(ValueError,'word-group'):
            self.check(True,refused_receipt=refused.replace('ARM_WORD_GROUPS,0\n','ARM_WORD_GROUPS,5\n'))


class MixedArenaQualificationTests(unittest.TestCase):
    """Keep an ordinary image run and both injected publisher refusals in native qualification."""

    def test_partial_publication_must_prove_the_second_slot_refusal(self):
        """A first-slot failure cannot satisfy the run that must release a partially published arena."""
        checks = Mock()
        checks.build.return_value = (dict(exit_code=0), 'binary')
        checks.command.side_effect = [
            dict(exit_code=0, output='MIXED_ARENA_SINGLE_OK\nMIXED_ARENA_OK\n'),
            dict(exit_code=0, output='MIXED_ARENA_PUBLISH_REFUSAL,0\nMIXED_ARENA_OK\n'),
            dict(exit_code=0, output='MIXED_ARENA_PUBLISH_REFUSAL,0\nMIXED_ARENA_OK\n',
                 log='mixed-arena-refuse-1-run.log')]
        with self.assertRaisesRegex(RuntimeError, 'mixed-arena-refuse-1-run'):
            ci.qualify_mixed_arena(checks, 'compiler', dict(system='Linux', machine='x86_64'))


class ReadWidthQualificationTests(unittest.TestCase):
    """New opcode coverage cannot be substituted by a generic golden, stale file or foreign image."""

    def proof(self, isa='arm64'):
        """Construct an independent transcript for the two public bank histories of each new form."""
        return dict(schema=1, isa=isa, rows=[dict(opcode=opcode, dirty=dirty,
            kind='CheckedReadBody', calls=40000, operations=dirty*40000)
            for opcode in (125, 126, 127, 128) for dirty in (3, 7)])

    def test_complete_native_activity_and_all_incomplete_substitutions(self):
        """Both ISAs need eight exact rows; missing/duplicate/foreign/zero/boolean values fail."""
        for isa in ('arm64', 'x86_64'):
            self.assertEqual(ci.validate_read_width_proof(self.proof(isa), isa), self.proof(isa))
        negatives = []
        missing = self.proof()
        missing['rows'].pop()
        negatives.append(missing)
        duplicate = self.proof()
        duplicate['rows'][-1] = dict(duplicate['rows'][0])
        negatives.append(duplicate)
        negatives.append(self.proof('x86_64'))
        for key, value in (('kind', 'PurePrefix'), ('kind', 'ClosedRegisterLoop'),
                           ('calls', 0), ('operations', 0), ('operations', 40001),
                           ('dirty', 6), ('opcode', 124), ('calls', True)):
            # Mutate one execution fact at a time, retaining every other well-formed row.
            proof = self.proof()
            proof['rows'][0][key] = value
            negatives.append(proof)
        for proof in negatives:
            with self.subTest(proof=proof), self.assertRaises(ValueError):
                ci.validate_read_width_proof(proof, 'arm64')

    def test_fresh_execution_and_sealed_source_are_required(self):
        """Exercise the real gate with inert tools; stale proof, failed run and changed source fail."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root/'test_width.nim'
            source.write_text('inert source')
            source.with_suffix('.output').write_text('width passed\n')
            profile = dict(defines=['pvmArm64Jit', 'pvmSharedAsyncWitness'], includes=['pvm_jit'],
                           libraries=[], observers=[], prepared=False)
            checks = Mock(folder=root/'checks')
            binary = root/'inert-image'
            binary.write_bytes(b'inert image')
            checks.build.return_value = (dict(exit_code=0, log='build.log'), binary)
            failure = None

            def command(arguments, name, environment, timeout):
                """Only the current successful process writes its proof, like the real native witness."""
                path = Path(environment['RAGNAROK_TEST_EVIDENCE'])/'pvm_read_widths_arm64.json'
                if failure not in ('missing', 'exit'):
                    # The real decoder must reject truncated evidence even after a green process exit.
                    encoded = json.dumps(self.proof())
                    path.write_text(encoded[:-1] if failure == 'truncated' else encoded)
                if failure == 'source':
                    source.write_text('changed source')
                return dict(exit_code=1 if failure == 'exit' else 0,
                            output='width passed\n', log=name+'.log')

            checks.command.side_effect = command
            with patch.object(ci, 'ROOT', root), \
                    patch.object(ci, 'NATIVE_REQUIREMENTS', {'pvm_shared_read_widths_arm': profile}), \
                    patch.object(ci, 'read_width_source_paths', return_value=[source]), \
                    patch.object(ci, 'unit_source', return_value=source), \
                    patch.object(ci, 'unit_environment', return_value={}):
                result = ci.qualify_read_widths(checks, 'compiler', dict(system='Linux', machine='aarch64'))
                self.assertEqual(result['status'], 'passed')
                for failure, error in (('missing', FileNotFoundError), ('exit', RuntimeError),
                                       ('truncated', json.JSONDecodeError),
                                       ('source', ValueError)):
                    # Leave the preceding green proof in place; the gate must retire it before running.
                    with self.subTest(failure=failure), self.assertRaises(error):
                        ci.qualify_read_widths(checks, 'compiler', dict(system='Linux', machine='aarch64'))


if __name__=='__main__':
    unittest.main()
