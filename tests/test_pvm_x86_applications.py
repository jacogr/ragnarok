# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Host and build-policy tests for the shared exact-state native application cohort; never execute a compiler."""
import unittest
from pathlib import Path
from pvm_arm64_jit_applications import application_host, application_defines


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

    def test_historical_baseline_remains_buildable_and_explicit(self):
        """A master predating x86 generation retains its real interpreted fallback; later x86 parents can reuse that backend."""
        self.assertEqual(application_defines('x86_64','baseline',False),['pvmArm64Jit'])
        self.assertEqual(application_defines('x86_64','baseline',True),['pvmX86Jit'])
        with self.assertRaises(ValueError): application_defines('x86','jit',True)
