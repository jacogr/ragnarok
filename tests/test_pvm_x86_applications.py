# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Host and build-policy tests for the shared exact-state native application cohort; never execute a compiler."""
import unittest
from pvm_jit_platform import native_defines
from pathlib import Path
from pvm_arm64_jit_applications import application_host, application_defines
from pvm_x86_jit_profile import selected_symbol, profile_environment, matching_native_activity, exclusive_costs


class NativeApplicationPolicyTests(unittest.TestCase):
    """A guest ISA or role cannot disguise an unsupported host or create unequal current policy images."""
    def test_make_provisions_both_offline_reference_builds(self):
        """A clean CI runner must fetch both locked references before the offline shared harness starts."""
        make=(Path(__file__).resolve().parents[1]/'Makefile').read_text()
        target=make.split('bench-pvm-x86-applications: toolchain sources rust-tools\n',1)[1]
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
