# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check tool replacement, recovery and cleanup with inert local files and processes."""
import fcntl
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import managed_tools


class ManagedTools(unittest.TestCase):
    """Failed upgrades preserve old tools; successful upgrades and cleanup retire obsolete output."""

    def setUp(self):
        """Own all test installations and locks in a disposable directory."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.tools = self.root/'build-tools'
        self.destination = self.tools/'toolchain'
        self.destination.mkdir(parents=True)
        (self.destination/'old').write_bytes(b'old tool')
        patcher = patch.object(managed_tools, 'TOOLS', self.tools)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_upgrade_retires_only_obsolete_inputs(self):
        """Only requested archives survive a successful pin replacement at the stable path."""
        (self.destination/'current.archive').write_bytes(b'verified by consumer')
        (self.destination/'retired.archive').write_bytes(b'old archive')
        with managed_tools.operation(self.destination), managed_tools.replacement(
                self.destination, ('current.archive',)):
            self.assertEqual((self.destination/'current.archive').read_bytes(), b'verified by consumer')
            self.assertFalse((self.destination/'old').exists())
            (self.destination/'new').write_bytes(b'new tool')
        self.assertEqual(sorted(path.name for path in self.tools.iterdir()), ['.lock', 'toolchain'])
        self.assertEqual(sorted(path.name for path in self.destination.iterdir()), ['current.archive', 'new'])

    def test_legacy_location_retired_only_after_success(self):
        """Updaters retain the old layout through a failed migration and remove it after success."""
        legacy = self.root/'build/toolchain'
        legacy.mkdir(parents=True)
        (legacy/'old').write_bytes(b'legacy tool')
        with self.assertRaises(RuntimeError):
            with managed_tools.operation(self.destination), managed_tools.replacement(self.destination):
                raise RuntimeError('failed migration')
        self.assertEqual((legacy/'old').read_bytes(), b'legacy tool')
        with managed_tools.operation(self.destination), managed_tools.replacement(self.destination):
            (self.destination/'new').write_bytes(b'verified replacement')
        self.assertFalse(legacy.exists())

    def test_native_reuse_and_invalidation(self):
        """Source, compiler, flags and ABI damage invalidate retained objects; unchanged builds reuse them."""
        source = self.root/'bridge.c'
        source.write_bytes(b'bridge')
        library = self.destination/'library.so'
        object_file = self.destination/'cached.o'
        commands = [['inert-compiler', '--version']]
        with patch.object(managed_tools.subprocess, 'check_output', return_value='compiler 1') as version:
            for change in ('first', 'reuse', 'source', 'compiler', 'flags', 'damage'):
                # Each transition independently exercises the same production cache boundary.
                if change == 'source':
                    source.write_bytes(b'updated bridge')
                elif change == 'compiler':
                    version.return_value = 'compiler 2'
                elif change == 'flags':
                    self.enterContext(patch.dict(managed_tools.os.environ, {'CFLAGS': '-O1'}))
                elif change == 'damage':
                    library.write_bytes(b'tampered library')
                with self.subTest(change=change), managed_tools.native_cache(
                        self.destination, [source], commands, [library]) as reusable:
                    self.assertEqual(object_file.exists(), change == 'reuse')
                    self.assertEqual(reusable, change == 'reuse')
                    # Rust builders retain their tests/builds; C builders can reuse validated output.
                    object_file.write_bytes(b'compiled object')
                    library.write_bytes(b'validated ABI')

    def test_failed_or_cancelled_upgrade_restores_old_tool(self):
        """Build errors and cancellation never publish partial output or strand the preceding tool."""
        for error in (RuntimeError, KeyboardInterrupt):
            with self.subTest(error=error), self.assertRaises(error):
                with managed_tools.operation(self.destination), managed_tools.replacement(self.destination):
                    (self.destination/'partial').write_bytes(b'incomplete')
                    raise error('interrupted build')
            self.assertEqual((self.destination/'old').read_bytes(), b'old tool')
            self.assertFalse((self.destination/'partial').exists())

    def test_recovers_interrupted_replacement(self):
        """The next installer rolls back an abandoned build before inspecting installed output."""
        self.destination.rename(self.tools/'.toolchain-previous')
        self.destination.mkdir()
        (self.destination/'partial').touch()
        with managed_tools.operation(self.destination):
            self.assertEqual((self.destination/'old').read_bytes(), b'old tool')
            self.assertFalse((self.destination/'partial').exists())

    def test_make_clean_preserves_tools_and_explicit_cleanup_removes_them(self):
        """Exercise the actual Make targets without launching setup, compilers or downloads."""
        source = Path(__file__).resolve().parents[1]
        shutil.copyfile(source/'Makefile', self.root/'Makefile')
        scripts = self.root/'tools'
        scripts.mkdir()
        for name in ('managed_tools.py', 'toolchain_archives.py'):
            shutil.copyfile(source/'tools'/name, scripts/name)
        output = self.root/'build'
        output.mkdir()
        (output/'artifact').touch()
        library = self.tools/'crypto/library.so'
        library.parent.mkdir()
        library.write_bytes(b'inert native library')
        for target in ('clean', 'clean-tools'):
            result = subprocess.run(['make', target, 'PYTHON='+sys.executable], cwd=self.root,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            if target == 'clean':
                # Cleaning project output must preserve the installed tool bytes.
                self.assertFalse(output.exists())
                self.assertEqual((self.destination/'old').read_bytes(), b'old tool')
                self.assertEqual(library.read_bytes(), b'inert native library')
        self.assertEqual([path.name for path in self.tools.iterdir()], ['.lock'])

    def test_cleanup_uses_the_installers_lock(self):
        """Cleanup cannot delete a live installer's files or replace the lock inode."""
        script = ('from pathlib import Path; import sys, managed_tools; '
                  'managed_tools.TOOLS=Path(sys.argv[1]); '
                  'print("ready", flush=True); managed_tools.clean()')
        with managed_tools.operation(self.destination):
            lock = self.tools/'.lock'
            inode = lock.stat().st_ino
            process = subprocess.Popen([sys.executable, '-c', script, str(self.tools)],
                                       cwd=Path(managed_tools.__file__).parent,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.assertEqual(process.stdout.readline().strip(), 'ready')
                # A second nonblocking acquisition proves that another process cannot enter cleanup.
                with lock.open('a') as competing:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(competing, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertIsNone(process.poll())
                self.assertTrue((self.destination/'old').exists())
            except BaseException:
                process.kill()
                process.communicate()
                raise
        try:
            _, errors = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, errors)
            self.assertFalse(self.destination.exists())
            self.assertEqual(lock.stat().st_ino, inode)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
