# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check shared native compiler profiles and isolated workspaces.

Exposes VerificationProfiles for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import fcntl
import io
import sys
import unittest
from unittest.mock import Mock, patch
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from native_checks import NativeChecks
from setup_nimony import cache_directory
from harness_fixtures import temporary_folder


# Keep profiles ownership and failure safeguards independent of other verification groups.
class VerificationProfiles(unittest.TestCase):
    # Unit and E2E compilation must retain identical checked platform profiles in independent workspaces.
    def test_shared_native_compiler_profiles(self):
        for system in ('Linux', 'Darwin'):
            # Command planning exercises both hosts without executing an unrelated compiler or native ABI.
            with self.subTest(system=system), patch('native_checks.platform.system', return_value=system):
                caches = set()
                for group in ('unit', 'failures', 'e2e'):
                    # Equal source names in different groups must never share executable or compiler outputs.
                    checks = NativeChecks(ROOT/'build/fixture-groups'/group)
                    with patch.object(checks, 'command', return_value=dict(exit_code=0)) as command:
                        _, binary = checks.build(Path('/fixture/nimony'), ROOT/'src/ragnarok.nim', 'peer',
                                                  quic_library=Path('/fixture/libquic'), defines=('integration',))
                    arguments = command.call_args.args[0]
                    self.assertEqual(binary.parent, checks.folder)
                    for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
                                 '--boundchecks:on', '--passC:-flto', '--passL:-flto', '-d:integration'):
                        # Every executable retains guards, ARC, native optimization and the explicit feature profile.
                        self.assertIn(flag, arguments)
                    self.assertEqual('--passL:-fuse-ld=lld' in arguments, system == 'Linux')
                    caches.add(next(arg for arg in arguments if str(arg).startswith('--nimcache:')))
                self.assertEqual(len(caches), 3)


    # Reuse is opt-in, preserves checked flags, and keeps different main binaries independently named.
    def test_contract_profile_reuse(self):
        with temporary_folder() as folder:
            checks = NativeChecks(folder/'contracts', reuse_builds=True)
            with patch.object(checks, 'command', return_value=dict(exit_code=0, elapsed_seconds=0)) as command, patch(
                    'sys.stdout', new_callable=io.StringIO):
                _, first = checks.build(folder/'compiler/nimony', folder/'sources/one.nim', 'one')
                args = command.call_args.args[0]
                _, second = checks.build(folder/'compiler/nimony', folder/'sources/two.nim', 'two')
                other = command.call_args.args[0]
                self.assertNotEqual(first, second)
                self.assertEqual(next(a for a in args if str(a).startswith('--nimcache:')),
                                 next(a for a in other if str(a).startswith('--nimcache:')))
                self.assertIn('--out:'+str(first), args)
                self.assertIn('--out:'+str(second), other)
                for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
                             '--boundchecks:on', '--passC:-flto', '--passL:-flto'):
                    # Cache reuse cannot substitute weaker compiler flags for the original checked profile.
                    self.assertIn(flag, args)

    # Compiler, group, source directory and ordered feature/observer arguments isolate incompatible caches.
    def test_contract_profile_boundaries(self):
        with temporary_folder('a', 'b') as folder, patch('sys.stdout', new_callable=io.StringIO):
            def planned(compiler=None, directory=None, group=None, **options):
                # Mock only execution; exercise the actual profile and path construction.
                checks = NativeChecks(folder/(group or 'contracts'), reuse_builds=True)
                with patch.object(checks, 'command', return_value=dict(exit_code=0, elapsed_seconds=0)) as command:
                    checks.build(compiler or folder/'compiler/nimony', (directory or folder/'source')/'driver.nim',
                                 'driver', **options)
                return next(a for a in command.call_args.args[0] if str(a).startswith('--nimcache:'))
            baseline = planned()
            variants = [planned(compiler=folder/'other/nimony'), planned(directory=folder/'other-source'),
                        planned(group='other-group'), planned(defines=('enabled',)),
                        planned(cflags=('-Dobservation=on',)), planned(crypto_library=folder/'a'),
                        planned(crypto_library=folder/'b'), planned(native_libraries=(folder/'a', folder/'b')),
                        planned(native_libraries=(folder/'b', folder/'a'))]
            self.assertEqual(len(set([baseline, *variants])), len(variants)+1)

    # Changed native bytes or public headers cannot reuse an executable/intermediate from the old profile.
    def test_contract_native_input_invalidation(self):
        with temporary_folder('library') as folder, patch('native_checks.ROOT', folder), patch(
                'sys.stdout', new_callable=io.StringIO):
            header = folder/'native/crypto/bridge.h'
            header.parent.mkdir(parents=True)
            header.write_text('first')
            checks = NativeChecks(folder/'contracts', reuse_builds=True)
            def planned():
                # Identical paths must still change identity when the consumed bytes change.
                with patch.object(checks, 'command', return_value=dict(exit_code=0, elapsed_seconds=0)) as command:
                    checks.build(folder/'compiler/nimony', folder/'driver.nim', 'driver', crypto_library=folder/'library')
                return next(a for a in command.call_args.args[0] if str(a).startswith('--nimcache:'))
            first = planned()
            (folder/'library').write_bytes(b'changed native bytes')
            second = planned()
            self.assertNotEqual(first, second)
            header.write_text('changed header')
            self.assertNotEqual(second, planned())

    # Concurrent builds cannot write shared intermediates; command failure releases the descriptor lock.
    def test_contract_cache_lock_release(self):
        with temporary_folder() as folder, patch('sys.stdout', new_callable=io.StringIO):
            compiler = folder/'compiler/nimony'
            checks = NativeChecks(folder/'contracts', reuse_builds=True)
            lock = cache_directory(compiler, checks.folder, 'builds').parent/'builds.lock'
            def failed(*args):
                # A separately opened descriptor must be excluded during the active build.
                with lock.open('a') as other:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
                raise RuntimeError('fixture build failed')
            with patch.object(checks, 'command', side_effect=failed), self.assertRaisesRegex(RuntimeError, 'build failed'):
                checks.build(compiler, folder/'source.nim', 'fixture')
            with lock.open('a') as other:
                # Error cleanup cannot strand subsequent local verification behind a stale lock.
                fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(other, fcntl.LOCK_UN)

    def test_e2e_profiles_share_application_entry(self):
        """Every feature profile builds the app, rather than reviving a QUIC or telemetry executable."""
        import e2e_checks
        profiles = [(e2e_checks.prepare_peer, 'ragnarok'),
                    (e2e_checks.prepare_integrated_peer, 'ragnarok-integration'),
                    (e2e_checks.prepare_offload_peer, 'ragnarok-offload')]
        for prepare, name in profiles:
            # The build/fixture boundaries are inert; assertions inspect the real scheduling callable.
            with self.subTest(profile=name):
                build = Mock(return_value=({'exit_code': 0}, Path('/fixture')/name))
                context = SimpleNamespace(compiler=Path('/fixture/nimony'), crypto=Path('/fixture/crypto'),
                    quic=Path('/fixture/quic'), bs=Path('/fixture/bs'), report={},
                    checks=SimpleNamespace(build=build, folder=Path('/fixture/e2e')))
                with patch('test_quic_offload.corpus', return_value=(Path('/fixture/wire'), {})):
                    prepare(context)
                build.assert_called_once()
                self.assertEqual(build.call_args.args[1], ROOT/'src/ragnarok.nim')
                self.assertEqual(build.call_args.args[2], name)


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
