# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Fuzz orchestration must reject unbounded counts, stale/partial evidence and changed seed bytes."""
import hashlib
import os
import sys
import time
import unittest
from unittest.mock import patch
from harness_fixtures import temporary_folder
import fuzz_pvm_program as fuzz
import native_checks


class ProgramFuzzToolTests(unittest.TestCase):
    """Native Nim owns properties; these checks cover only tool selection, provenance and failure verdicts."""

    def test_source_provenance_tracks_current_bytes(self):
        """Source edits update the evidence map without requiring the retired cache-epoch helper."""
        with temporary_folder() as root:
            path = root/'target.nim'
            path.write_bytes(b'first')
            with patch.object(fuzz, 'ROOT', root), patch.object(
                    fuzz, 'discover_project_sources', return_value={path}):
                self.assertEqual(fuzz.source_hashes(), {'target.nim': hashlib.sha256(b'first').hexdigest()})
                path.write_bytes(b'other')
                self.assertEqual(fuzz.source_hashes(), {'target.nim': hashlib.sha256(b'other').hexdigest()})

    def test_count_is_canonical_and_finite(self):
        """Every campaign has an explicit count beyond seed initialization and below the operational ceiling."""
        for text, expected in [('16', 16), ('100000', 100000), ('1000000', 1000000)]:
            self.assertEqual(fuzz.run_count(text), expected)
        for text in ['', '0', '15', '016', '+16', '-16', ' 16', '16 ', '1000001', '1e6', None, True]:
            with self.assertRaises(ValueError):
                fuzz.run_count(text)

    def test_runtime_selection_is_explicit_or_unique(self):
        """An absent or ambiguous toolchain library cannot silently select another backend or download a runtime."""
        with temporary_folder() as root:
            with self.assertRaises(ValueError):
                fuzz.select_runtime(root)
            runtime = root/'lib/linux/libclang_rt.fuzzer_no_main-x86_64.a'
            runtime.parent.mkdir(parents=True)
            runtime.write_bytes(b'first')
            self.assertEqual(fuzz.select_runtime(root), runtime.resolve())
            second = runtime.with_name('libclang_rt.fuzzer_no_main-aarch64.a')
            second.write_bytes(b'second')
            with self.assertRaises(ValueError):
                fuzz.select_runtime(root)
            self.assertEqual(fuzz.select_runtime(root, str(second)), second.resolve())
            with self.assertRaises(ValueError):
                fuzz.select_runtime(root, str(root/'missing.a'))

    def test_seed_bytes_are_independent_expectations(self):
        """Missing, changed and oversized seed data fail before any mutable corpus or native process starts."""
        with temporary_folder() as root:
            path = root/'seed.bin'
            data = b'original'
            path.write_bytes(data)
            contract = ('RAGNAROK_PVM_PROGRAM_FUZZ', root, ((path, hashlib.sha256(data).hexdigest()),))
            with patch.dict(fuzz.FIXTURE_CONTRACTS, pvm_program_fuzz=contract):
                self.assertEqual(fuzz.seed_files(), [path])
                path.write_bytes(b'changed')
                with self.assertRaises(ValueError):
                    fuzz.seed_files()
                path.write_bytes(b'x'*(fuzz.MAX_INPUT+1))
                with self.assertRaises(ValueError):
                    fuzz.seed_files()
                path.unlink()
                with self.assertRaises(ValueError):
                    fuzz.seed_files()

    def test_partial_or_failed_campaign_cannot_pass(self):
        """An exact completed run and real coverage initialization are required independently of process exit status."""
        valid = 'INFO: Loaded 1 modules (30 inline 8-bit counters)\nINFO: Loaded 1 PC tables\n#100 DONE cov: 12 ft: 30 corp: 4/20b\n'
        self.assertEqual(fuzz.campaign_observation(valid, 100), dict(runs=100, coverage=12, features=30))
        for text in [valid.replace('#100', '#99'), valid.replace('cov: 12', 'cov: 0'),
                     valid.replace('PC tables', 'unrelated'), valid+'#100 DONE cov: 12 ft: 30\n',
                     valid+'ERROR: sanitizer failure\n', valid+'runtime error: invalid access\n', '']:
            with self.assertRaises(ValueError):
                fuzz.campaign_observation(text, 100)

    def test_shared_builder_preserves_instrumentation_and_compiler_environment(self):
        """Coverage link flags and selected Clang reach the actual checked builder; ordinary callers keep their defaults."""
        with temporary_folder() as root, patch.object(native_checks, 'ROOT', root):
            source = root/'main.nim'
            source.write_text('discard')
            checks = native_checks.NativeChecks(root/'out', lto=False)
            environment = {'PATH': '/selected/clang'}
            with patch.object(checks, 'command', return_value=dict(exit_code=0)) as command:
                checks.build(root/'nimony', source, 'fuzz', cflags=('-fsanitize=address',),
                             link_flags=('-fsanitize=address', '/owned/driver.o'), environment=environment)
            arguments = [str(value) for value in command.call_args.args[0]]
            for expected in ['--mm:arc', '--cc:clang', '-d:release', '--boundchecks:on',
                             '--passC:-fsanitize=address', '--passL:-fsanitize=address', '--passL:/owned/driver.o']:
                self.assertIn(expected, arguments)
            self.assertNotIn('--passC:-flto', arguments)
            self.assertIs(command.call_args.kwargs['environment'], environment)
            with patch.object(checks, 'command', return_value=dict(exit_code=0)) as command:
                checks.build(root/'nimony', source, 'ordinary')
            self.assertNotIn('environment', command.call_args.kwargs)

    def test_process_group_completion_and_timeout(self):
        """A timed-out invocation retires its descendant before it can publish a delayed result."""
        with temporary_folder() as root, patch.object(fuzz, 'ROOT', root):
            row = fuzz.run_group([sys.executable, '-c', "print('complete')"],
                                 'complete', root, dict(os.environ), 5)
            self.assertEqual(row['exit_code'], 0)
            self.assertFalse(row['timed_out'])
            self.assertEqual(row['output'], 'complete\n')
            child = "from pathlib import Path; import time; Path('ready').touch(); time.sleep(3); Path('late').touch()"
            parent = "import subprocess, sys; subprocess.Popen([sys.executable, '-c', sys.argv[1]]); import time; time.sleep(10)"
            row = fuzz.run_group([sys.executable, '-c', parent, child],
                                 'timeout', root, dict(os.environ), 2)
            self.assertTrue((root/'ready').exists())
            self.assertTrue(row['timed_out'])
            self.assertNotEqual(row['exit_code'], 0)
            time.sleep(1.2)  # The retired descendant must never reach its delayed write.
            self.assertFalse((root/'late').exists())
