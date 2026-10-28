# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Refuse mismatched CI hosts and missing native execution before accepting PVM qualification."""
from contextlib import ExitStack
from pathlib import Path
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
    def test_both_owner_suites_precede_success(self):
        """The native CI gate requires regular and refused-storage owner policies on either architecture."""
        checks = Mock()
        checks.command.return_value = dict(exit_code=0, log='policy.log')
        rows = ci.qualify_policy(checks)
        self.assertEqual([row['suite'] for row in rows],
                         ['pvm_runtime_policy', 'pvm_runtime_policy_refused'])
        for call in checks.command.call_args_list:
            self.assertIn('--suite', call.args[0])
        checks.command.return_value = dict(exit_code=1, log='failure.log')
        with self.assertRaisesRegex(RuntimeError, 'failure.log'):
            ci.qualify_policy(checks)


class QualificationTests(unittest.TestCase):
    def check(self, native, receipt=None, build_error=False):
        """Model tool process boundaries; all native assertions stay in the maintained Nim/C witnesses."""
        class Checks:
            folder=Path('/tmp/pvm-ci-test')
            builds=[]
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
                    output=receipt if receipt is not None else (('TRANSFER_STATS,1,2\n' if native else '')+'ARM_SELF_REGION_CASES,1920\n')
                elif name=='witness-refused-run':
                    output='TRANSFER_STATS,0,0\nARM_SELF_REGION_CASES,1920\n'
                elif '-move-run' in name:
                    output='0\n0\n'
                return dict(exit_code=0,output=output)
        checks=Checks()
        return qualify(checks,Path('/compiler'),native=native),checks.builds

    def test_native_and_unavailable_profiles(self):
        """The explicit ARM-only helper retains off-platform fallback controls independently of x86 qualification."""
        for native in (True,False):
            rows,builds=self.check(native)
            self.assertEqual(len(rows),9)
            witness=next(flags for name,flags in builds if name=='witness')
            self.assertEqual(witness,['pvmArm64Jit'] if native else [])
            refused=next(flags for name,flags in builds if name=='witness-refused')
            self.assertIn('pvmArm64JitRefuse',refused)

    def test_no_native_execution_and_compiler_failure(self):
        """Zero, missing or duplicate native counters and failed compilation never qualify the runner."""
        for receipt in ('','TRANSFER_STATS,0,0\n','TRANSFER_STATS,1,2\nTRANSFER_STATS,1,2\n'):
            with self.subTest(receipt=receipt),self.assertRaises(ValueError):
                self.check(True,receipt+'ARM_SELF_REGION_CASES,1920\n')
        with self.assertRaisesRegex(RuntimeError,'compiler failure'):
            self.check(True,build_error=True)


    def test_complete_single_block_receipt_is_required(self):
        """A valid native transfer cannot disguise absent, incomplete or repeated new region coverage."""
        for marker in ('', 'ARM_SELF_REGION_CASES,1919\n',
                       'ARM_SELF_REGION_CASES,1920\nARM_SELF_REGION_CASES,1920\n'):
            with self.subTest(marker=marker),self.assertRaisesRegex(ValueError,'one-block'):
                self.check(True,'TRANSFER_STATS,1,2\n'+marker)


if __name__=='__main__':
    unittest.main()
