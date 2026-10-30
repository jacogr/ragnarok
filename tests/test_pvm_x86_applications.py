# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Host and build-policy tests for the shared exact-state native application cohort; never execute a compiler."""
import unittest
from harness_fixtures import make_plan
import json
from tempfile import TemporaryDirectory
from unittest.mock import patch
from pvm_jit_platform import native_defines
from pathlib import Path
from pvm_arm64_jit_applications import application_host, application_defines
from pvm_x86_jit_profile import selected_symbol, profile_environment, matching_native_activity, exclusive_costs, profile_plan, run as profile_run


class NativeApplicationPolicyTests(unittest.TestCase):
    """A guest ISA or role cannot disguise an unsupported host or create unequal current policy images."""
    def test_make_provisions_both_offline_reference_builds(self):
        """A clean CI runner must fetch both locked references before the offline shared harness starts."""
        target=make_plan('bench-pvm-x86-applications', skip=('toolchain','sources','rust-tools'))
        for crate in ('polkavm','polkavm_doom'):
            fetch='cargo fetch --locked --manifest-path tests/performance/'+crate+'/Cargo.toml'
            self.assertIn(fetch,target)
            self.assertLess(target.index(fetch),target.index('tools/pvm_x86_jit_applications.py'))

    def test_exact_supported_host_matrix(self):
        """Only the maintained native CPU/OS pairs may emit an architecture's code."""
        for system in ('Linux','Darwin','Windows'):
            for machine in ('x86_64','amd64','arm64','aarch64','i686','riscv64'):
                self.assertEqual(application_host('x86_64',system,machine),
                    system=='Linux' and machine in ('x86_64','amd64'))
                self.assertEqual(application_host('arm64',system,machine),
                    system in ('Linux','Darwin') and machine in ('arm64','aarch64'))
        with self.assertRaises(ValueError): application_host('x86','Linux','i686')

    def test_current_policies_have_identical_native_defines(self):
        """Interpretation is a runtime selection within the same binary, on either supported host backend."""
        for architecture in ('arm64','x86_64'):
            left=application_defines(architecture,'interpreter',True)
            right=application_defines(architecture,'jit',True)
            self.assertEqual(left,right)
        self.assertEqual(application_defines('x86_64','jit',True),['pvmX86Jit'])
        self.assertEqual(application_defines('arm64','jit',True),['pvmArm64Jit'])
        for architecture,machine in (('arm64','aarch64'),('x86_64','x86_64')):
            self.assertEqual(application_defines(architecture,'jit',True),native_defines('Linux',machine))

    def test_historical_baseline_remains_buildable_and_explicit(self):
        """A master predating x86 generation retains its real interpreted fallback; later x86 parents can reuse that backend."""
        self.assertEqual(application_defines('x86_64','baseline',False),['pvmArm64Jit'])
        self.assertEqual(application_defines('x86_64','baseline',True),['pvmX86Jit'])
        with self.assertRaises(ValueError): application_defines('x86','jit',True)


class X86ProfileScopeTests(unittest.TestCase):
    """Profiles require one actual text symbol and exactly the checked application policy/input framing."""
    def test_exact_symbol_and_refusals(self):
        """Caller references, absent symbols and duplicated definitions cannot authorize a scope."""
        self.assertEqual(selected_symbol('100 t runPreparedKernel_17_step\n', 'runPreparedKernel'),
                         'runPreparedKernel_17_step')
        for text in ('', ' U runPreparedKernel_17_step\n',
                     '100 d runPreparedKernel_17_step\n',
                     '100 t runPreparedKernel_17_step\n200 T runPreparedKernel_18_step\n'):
            with self.assertRaises(ValueError): selected_symbol(text, 'runPreparedKernel')

    def test_maintained_workload_environment(self):
        """Both policy profiles retain thirteen complete calls and the same reference-prepared bytes."""
        for case, limit in (('sieve',100000), ('pinky',1), ('tick',0)):
            left, right = (profile_environment(case, limit, role) for role in ('interpreted','jit'))
            self.assertEqual(left.pop('RAGNAROK_PVM_BACKEND'), 'interpreted')
            self.assertEqual(right.pop('RAGNAROK_PVM_BACKEND'), 'jit')
            self.assertEqual(left, right)
            self.assertEqual(left['RAGNAROK_PVM_SIEVE_SAMPLES'], '13')
            self.assertEqual(left['RAGNAROK_PVM_LOCAL_ONECALL'], '0')


    def test_minimal_diagnostic_keeps_all_existing_arm_scopes(self):
        """An explicit extra scope measures the regressed workload without replacing either DOOM phase or changing x86 defaults."""
        original=profile_plan('arm64')
        expanded=profile_plan('arm64',include_minimal=True)
        self.assertEqual(expanded['cases'],(('sieve',100000),('minimal',100000),('init',0),('tick',0)))
        self.assertEqual(expanded['roles'],original['roles'])
        self.assertEqual(profile_plan('x86_64')['cases'],(('sieve',100000),('pinky',1),('tick',0)))
        environment=profile_environment('minimal',100000,'jit','arm64')
        self.assertEqual(environment['RAGNAROK_PVM_GUEST'],'minimal')
        self.assertIn('pvm-arm64-applications/inputs/minimal/100000',environment['RAGNAROK_PVM_SIEVE_INPUT'])
        self.assertEqual(environment['RAGNAROK_PVM_SIEVE_SAMPLES'],'13')

    def test_x86_initialization_is_an_explicit_additional_scope(self):
        """A coverage investigation adds initialization without removing any original policy/workload or checked call."""
        original=profile_plan('x86_64',paired_baseline=True)
        expanded=profile_plan('x86_64',paired_baseline=True,include_init=True)
        self.assertEqual(expanded['roles'],original['roles'])
        self.assertEqual(expanded['cases'],(('sieve',100000),('pinky',1),('init',0),('tick',0)))
        self.assertEqual([case for case in expanded['cases'] if case[0]!='init'],list(original['cases']))
        for role in expanded['roles']:
            env=profile_environment('init',0,role)
            self.assertEqual(env['RAGNAROK_PVM_DOOM_PHASE'],'init')
            self.assertEqual(env['RAGNAROK_PVM_SIEVE_SAMPLES'],'13')
            self.assertEqual(env['RAGNAROK_PVM_LOCAL_ONECALL'],'0')
        self.assertEqual(profile_plan('arm64',include_init=True)['cases'],
                         profile_plan('arm64')['cases'])
        make=(Path(__file__).resolve().parents[1]/'Makefile').read_text()
        self.assertIn('tools/pvm_x86_jit_profile.py --paired-baseline --include-init',make)

    def test_x86_minimal_adds_scope_without_replacing_original_cases(self):
        """A repeated minimal regression needs its own calibrated full invocation, with the ordinary kernel image and thirteen calls."""
        original=profile_plan('x86_64',paired_baseline=True,include_init=True)
        expanded=profile_plan('x86_64',paired_baseline=True,include_init=True,include_minimal=True)
        self.assertEqual(expanded['roles'],original['roles'])
        self.assertEqual(expanded['cases'],(('sieve',100000),('minimal',100000),('pinky',1),('init',0),('tick',0)))
        self.assertEqual(tuple(c for c in expanded['cases'] if c[0]!='minimal'),original['cases'])
        env=profile_environment('minimal',100000,'jit')
        self.assertEqual(env['RAGNAROK_PVM_GUEST'],'minimal')
        self.assertEqual(env['RAGNAROK_PVM_SIEVE_SAMPLES'],'13')
        self.assertIn('pvm-x86-applications/inputs/minimal/100000',env['RAGNAROK_PVM_SIEVE_INPUT'])

    def test_expanded_profile_runner_retains_ci_refusal_and_plan(self):
        """Wire the optional runner argument through to a durable complete plan without ever invoking native work locally."""
        with TemporaryDirectory() as folder, patch('pvm_x86_jit_profile.BUILD',Path(folder)), \
                patch.dict('os.environ',{'GITHUB_ACTIONS':'false'}):
            with self.assertRaisesRegex(RuntimeError,'CI-only'):
                profile_run('x86_64',False,True,True)
            report=json.loads((Path(folder)/'results.json').read_text())
            self.assertEqual(report['status'],'failed')
            self.assertEqual(report['profiles'],[])
            self.assertEqual(report['profile_roles'],['baseline','jit'])
            self.assertEqual(report['profile_cases'],[dict(case=case,limit=limit) for case,limit in
                (('sieve',100000),('pinky',1),('init',0),('tick',0))])


    def test_arm_profiles_compare_exact_parent_and_current(self):
        """The ARM diagnostic binds its own sealed cohort and both genuine DOOM phases, never x86 inputs."""
        plan=profile_plan('arm64')
        self.assertEqual(plan['roles'],('baseline','jit'))
        make=(Path(__file__).resolve().parents[1]/'Makefile').read_text()
        self.assertIn('profile-pvm-arm64-linux:\n',make)
        self.assertNotIn('profile-pvm-arm64-linux: bench-',make)
        self.assertEqual(plan['cases'],(('sieve',100000),('init',0),('tick',0)))
        self.assertEqual(plan['cohort'].name,'pvm-arm64-applications')
        for case,limit in plan['cases']:
            environment=profile_environment(case,limit,'jit','arm64')
            self.assertEqual(environment['RAGNAROK_PVM_SIEVE_SAMPLES'],'13')
            self.assertEqual(environment['RAGNAROK_PVM_LOCAL_ONECALL'],'0')
            if case in ('init','tick'):
                self.assertEqual(environment['RAGNAROK_PVM_DOOM_PHASE'],case)
            else:
                self.assertIn('pvm-arm64-applications/inputs',environment['RAGNAROK_PVM_SIEVE_INPUT'])
        baseline=profile_environment('sieve',100000,'baseline','arm64')
        current=profile_environment('sieve',100000,'jit','arm64')
        self.assertEqual(baseline.pop('RAGNAROK_PVM_BACKEND'),'')
        self.assertEqual(current.pop('RAGNAROK_PVM_BACKEND'),'jit')
        self.assertEqual(baseline,current)
        with self.assertRaises(ValueError):profile_plan('riscv64')
        self.assertEqual(profile_plan('x86_64')['roles'],('interpreter','jit'))
        paired=profile_plan('x86_64',paired_baseline=True)
        self.assertEqual(paired['roles'],('baseline','jit'))
        self.assertEqual(paired['cases'],profile_plan('x86_64')['cases'])
        self.assertIn('tools/pvm_x86_jit_profile.py --paired-baseline',make)

    def test_native_activity_cannot_turn_into_fallback(self):
        """Identical source/output alone cannot certify that an instrumented JIT actually executed native code."""
        measured = dict(fragments=2,calls=10,operations=40,code_bytes=128,branches=0,headers=0,compilation_ns=1)
        matching_native_activity(measured, dict(measured,compilation_ns=999))
        for key in ('fragments','calls','operations','code_bytes','branches','headers'):
            with self.assertRaises(ValueError): matching_native_activity(measured, dict(measured,**{key:measured[key]+1}))


    def test_zero_call_ancestry_is_not_self_work(self):
        """Calibrated return dumps retain synthetic ancestor arcs; counting them as self work doubles the total."""
        raw = '# callgrind format\npositions: line\nevents: Ir Bc\nsummary: 10 2\nfn=root\ncfn=scope\ncalls=0 0\n0 10 2\nfn=scope\n0 3\ncfn=child\ncalls=1 0\n0 7 2\nfn=child\n0 7 2\ntotals: 10 2\n'
        self.assertEqual(exclusive_costs(raw), {'child':{'Ir':7,'Bc':2},'scope':{'Ir':3,'Bc':0}})
        for changed in (raw.replace('fn=child\n0 7 2', 'fn=child\n0 6 2'),
                        raw.replace('positions: line', 'positions: instr line')):
            with self.assertRaises(ValueError): exclusive_costs(changed)


class ProductionJitPlatformTests(unittest.TestCase):
    """Only maintained OS/CPU pairs enable a native backend in the shipped peer and real CLI driver."""
    def test_supported_and_unsupported_matrix(self):
        """Thirty-two-bit x86 and untested hosts cannot accidentally select either 64-bit emitter."""
        for system in ('Linux','Darwin','Windows','FreeBSD'):
            for machine in ('x86_64','AMD64','arm64','aarch64','i686','riscv64'):
                expected = ['pvmX86Jit'] if system=='Linux' and machine in ('x86_64','AMD64') else (
                    ['pvmArm64Jit'] if system in ('Linux','Darwin') and machine in ('arm64','aarch64') else [])
                self.assertEqual(native_defines(system,machine), expected)
