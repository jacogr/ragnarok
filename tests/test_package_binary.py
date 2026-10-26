# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify archive contents, loader closure and strict failure handling without compiling fake peers."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from harness_fixtures import temporary_folder
import package_binary as packaging


class BinaryPackaging(unittest.TestCase):
    """Exercise packaging policy independently of the native per-platform smoke tests run by CI."""

    def fixture(self, root, system):
        """Supply inert payload bytes; process execution remains mocked in orchestration tests."""
        (root/'spec').mkdir()
        (root/'spec/toolchain.json').write_bytes((ROOT/'spec/toolchain.json').read_bytes())
        for name in ('LICENSE-APACHE', 'LICENSE-MIT'):
            (root/name).write_text(name)
        (root/'build').mkdir()
        (root/'build/ragnarok').write_bytes(b'peer')
        suffix = '.so' if system == 'Linux' else '.dylib'
        for directory, name in zip(('crypto', 'bandersnatch/target/release', 'quic'), packaging.LIBRARIES):
            # Only these explicit native ABIs belong in the archive, even with other build files present.
            folder = root/'build'/directory
            folder.mkdir(parents=True)
            (folder/(name+suffix)).write_bytes(name.encode())
        (root/'build/private-key').write_text('must stay outside the archive')
        return dict(system=system, platform='linux_amd64' if system == 'Linux' else 'macos_arm64')

    def test_archive_has_exact_payload_and_relocated_smoke(self):
        """Published checksums describe the actual archive; smoke commands use only its unpacked peer."""
        for system in ('Linux', 'Darwin'):
            with self.subTest(system=system), temporary_folder() as root:
                host = self.fixture(root, system)
                calls = []
                def command(checks, arguments, **options):
                    """Observe real orchestration while substituting only native tools and process execution."""
                    calls.append((arguments, options))
                    return 'revision\n' if arguments[0] == 'git' else ''
                with patch.object(packaging, 'host_pins', return_value=host), patch.object(
                        packaging.Package, 'dependencies', return_value=[]), patch.object(
                        packaging.Package, 'relocate'), patch.object(packaging.Package, 'verify') as verify, patch.object(
                        packaging.Package, 'command', command), patch.dict(os.environ, LD_LIBRARY_PATH='/foreign'):
                    archive = packaging.package(root)
                self.assertEqual(verify.call_count, 2)
                smoke = calls[1:]
                self.assertEqual([args[1] for args, _ in smoke], list(packaging.SMOKE_OPTIONS))
                for args, options in smoke:
                    # Tests cannot pass by executing the original build output or inheriting a loader override.
                    self.assertIn('/unpacked/bin/ragnarok', str(args[0]))
                    self.assertNotIn('LD_LIBRARY_PATH', options['env'])
                    self.assertEqual(options['cwd'].name, 'unpacked')
                checksum = Path(str(archive)+'.sha256').read_text().split()[0]
                self.assertEqual(checksum, hashlib.sha256(archive.read_bytes()).hexdigest())
                with tarfile.open(archive) as payload:
                    files = {member.name: payload.extractfile(member).read()
                             for member in payload.getmembers() if member.isfile()}
                manifest = json.loads(files.pop('manifest.json'))
                self.assertEqual(manifest['lto'], 'thin')
                self.assertEqual(manifest['revision'], 'revision')
                self.assertEqual(set(files), {'bin/ragnarok', 'LICENSE-APACHE', 'LICENSE-MIT',
                    *('lib/ragnarok/'+name+('.so' if system == 'Linux' else '.dylib') for name in packaging.LIBRARIES)})
                self.assertEqual(manifest['files'], {name: hashlib.sha256(data).hexdigest() for name, data in files.items()})

    def test_optional_guest_abi_and_upstream_licenses_follow_binary_dependencies(self):
        """A linked optional executor ships with its licenses; default archives retain their smaller closure."""
        with temporary_folder() as root:
            host = self.fixture(root, 'Linux')
            library = root/'build/polkavm/release/libragnarok_polkavm.so'
            library.parent.mkdir(parents=True)
            library.write_bytes(b'optional guest executor')
            upstream = root/'vendor/polkavm'
            upstream.mkdir(parents=True)
            for name in ('LICENSE-MIT', 'LICENSE-APACHE'):
                (upstream/name).write_text('upstream '+name)
            def command(checks, arguments, **options):
                """Only loader inspection and smoke execution are mocked; real archive bytes are verified."""
                return 'revision\n' if arguments[0] == 'git' else ''
            with patch.object(packaging, 'host_pins', return_value=host), patch.object(
                    packaging.Package, 'dependencies', return_value=[str(library)]), patch.object(
                    packaging.Package, 'relocate'), patch.object(packaging.Package, 'verify'), patch.object(
                    packaging.Package, 'command', command):
                archive = packaging.package(root)
            with tarfile.open(archive) as payload:
                self.assertEqual(payload.extractfile('lib/ragnarok/libragnarok_polkavm.so').read(),
                                 b'optional guest executor')
                for name in ('LICENSE-MIT', 'LICENSE-APACHE'):
                    self.assertEqual(payload.extractfile('licenses/polkavm/'+name).read(),
                                     ('upstream '+name).encode())

    def test_failed_smoke_removes_stale_artifacts(self):
        """A failed rebuilt peer cannot publish an old archive or checksum from a previous successful run."""
        with temporary_folder() as root:
            host = self.fixture(root, 'Linux')
            destination = root/'build/dist'
            destination.mkdir()
            for name in ('ragnarok-linux-amd64.tar.gz', 'ragnarok-linux-amd64.tar.gz.sha256'):
                (destination/name).write_text('stale success')
            def command(checks, arguments, **options):
                """Fail the last selftest after all earlier commands have succeeded."""
                if arguments[-1] == '--integration-selftest':
                    raise subprocess.CalledProcessError(7, arguments)
                return 'revision\n'
            with patch.object(packaging, 'host_pins', return_value=host), patch.object(
                    packaging.Package, 'relocate'), patch.object(packaging.Package, 'verify'), patch.object(
                    packaging.Package, 'command', command):
                with self.assertRaises(subprocess.CalledProcessError):
                    packaging.package(root)
            self.assertEqual(list(destination.iterdir()), [])
            self.assertTrue((root/'build/ci/binary-package.log').is_file())

    def test_closure_rejects_build_paths_and_unbundled_dependencies(self):
        """Only declared project ABIs and system dependencies may survive; all runpaths must be relative."""
        for system in ('Linux', 'Darwin'):
            binary, library = Path('/bundle/bin/ragnarok'), Path('/bundle/lib/ragnarok/library')
            checks = packaging.Package(system, io.StringIO())
            allowed = ['library', 'libc.so.6'] if system == 'Linux' else ['@rpath/library', '/usr/lib/libSystem.B.dylib']
            for dependencies in (allowed, ['/build/original/library'], ['@rpath/undeclared.dylib']):
                with self.subTest(system=system, dependencies=dependencies), patch.object(
                        checks, 'dependencies', return_value=dependencies), patch.object(
                        checks, 'rpaths', side_effect=lambda path: ['@executable_path/../lib/ragnarok' if path == binary else '@loader_path']), patch.object(
                        checks, 'command', side_effect=lambda args: '$ORIGIN/../lib/ragnarok' if args[-1] == binary else '$ORIGIN'):
                    if dependencies == allowed:
                        checks.verify(binary, [library])
                    else:
                        with self.assertRaisesRegex(ValueError, 'Unpackaged native dependency'):
                            checks.verify(binary, [library])
            with patch.object(checks, 'dependencies', return_value=allowed), patch.object(
                    checks, 'rpaths', return_value=['/build/old']), patch.object(checks, 'command', return_value='/build/old'):
                with self.assertRaisesRegex(ValueError, 'runpaths'):
                    checks.verify(binary, [library])

    def test_relocation_rewrites_transitive_project_dependencies_before_signing(self):
        """Both the peer and shared libraries lose original absolute paths; Mach-O edits precede signing."""
        binary = Path('/copy/bin/ragnarok')
        libraries = [Path('/copy/lib/ragnarok/crypto'), Path('/copy/lib/ragnarok/provider')]
        for system in ('Linux', 'Darwin'):
            checks = packaging.Package(system, io.StringIO())
            with self.subTest(system=system), patch.object(checks, 'dependencies',
                    return_value=['/original/provider']), patch.object(checks, 'rpaths',
                    return_value=['/original']), patch.object(checks, 'command') as command:
                checks.relocate(binary, libraries)
            commands = [call.args[0] for call in command.call_args_list]
            for path in (*libraries, binary):
                if system == 'Linux':
                    self.assertIn(['patchelf', '--replace-needed', '/original/provider', 'provider', path], commands)
                    self.assertIn(['patchelf', '--set-rpath',
                        '$ORIGIN/../lib/ragnarok' if path == binary else '$ORIGIN', path], commands)
                else:
                    self.assertIn(['install_name_tool', '-change', '/original/provider', '@rpath/provider', path], commands)
                    self.assertIn(['install_name_tool', '-delete_rpath', '/original', path], commands)
            if system == 'Darwin':
                self.assertEqual(commands[-3:], [['codesign', '--force', '--sign', '-', path]
                                                for path in (*libraries, binary)])

    def test_command_failures_remain_authoritative_and_logged(self):
        """A tool that writes diagnostics before failing cannot turn the package green."""
        log = io.StringIO()
        result = subprocess.CompletedProcess(['tool'], 9, 'stdout', 'failure details')
        with patch.object(packaging.subprocess, 'run', return_value=result):
            with self.assertRaises(subprocess.CalledProcessError):
                packaging.Package('Linux', log).command(['tool'])
        self.assertIn('failure details', log.getvalue())


if __name__ == '__main__':
    unittest.main()
