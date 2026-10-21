# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect discovery, process failure and fresh differential reports without invoking native tools."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from dependencies import ROOT
import pvm_reference as runner


class ReferenceRunnerTests(unittest.TestCase):
    """A reference or native failure and a changed generated corpus must fail the combined run."""

    def test_discovery_requires_every_probe_pair(self):
        """Unknown executable sources cannot silently escape reference/native coverage."""
        checks = runner.discover()
        self.assertEqual({item['binary'] for item in checks},
                         {'ragnarok-memory-probe', 'control', 'gas', 'hosts', 'jumps',
                          'limits', 'memory', 'registers', 'retry', 'validation'})
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            crate = Path(temporary)
            shutil.copytree(runner.CRATE/'src', crate/'src')
            (crate/'src/bin/unpaired.rs').write_text('fn main() {}\n')
            with self.assertRaisesRegex(ValueError, 'one reference declaration'):
                runner.discover(crate)

    def test_unsafe_or_duplicate_metadata_rejected(self):
        """Fixture paths, generators, suites and duplicate pairings are validated before execution."""
        declarations = [dict(suite='pvm_registers', input='../pvm-registers.bin'),
                        dict(suite='pvm_registers', generator='os'),
                        dict(suite='pvm_missing'), dict(suite='pvm_registers', skip=True),
                        dict(suite='pvm_registers', input='pvm-registers.bin', regenerate='x.bin')]
        for entry in declarations:
            with self.subTest(entry=entry), tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
                crate = Path(temporary)
                (crate/'src/bin').mkdir(parents=True)
                (crate/'src/main.rs').write_text(runner.MARKER+json.dumps(entry)+'\n')
                with self.assertRaises(ValueError):
                    runner.discover(crate)
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            crate = Path(temporary)
            (crate/'src/bin').mkdir(parents=True)
            text = runner.MARKER+json.dumps(dict(suite='pvm_registers'))+'\n'
            (crate/'src/main.rs').write_text(text)
            (crate/'src/bin/duplicate.rs').write_text(text)
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                runner.discover(crate)

    def test_process_status_logs_and_timeout(self):
        """A nonzero exit or timeout is preserved with diagnostics, including child-group cleanup."""
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            folder = Path(temporary)
            failed = runner.command([sys.executable, '-c', 'print("witness"); raise SystemExit(7)'],
                                    'failed', folder)
            self.assertEqual(failed['exit_code'], 7)
            self.assertIn('witness', (folder/'failed.log').read_text())
            timed = runner.command([sys.executable, '-c', 'import time; time.sleep(10)'],
                                   'timeout', folder, timeout=0.05)
            self.assertEqual(timed['exit_code'], 124)

    def test_combined_run_never_hides_failure(self):
        """Build/reference/native failures stop later probes and replace stale successful evidence."""
        sample = dict(binary='registers', suite='pvm_registers',
                      source='tests/reference/polkavm_memory/src/bin/registers.rs',
                      input='pvm-registers.bin')
        for failure in ('build', 'registers-reference', 'registers-native', None):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
                folder = Path(temporary)
                (folder/'results.json').write_text('{"status":"checks-passed"}')
                # Structured process observations replace actual tools; provenance still checks real pins.
                def observe(arguments, name, workspace):
                    return dict(command=list(map(str, arguments)), exit_code=7 if name == failure else 0,
                                log=str(workspace/(name+'.log')), elapsed_seconds=0)
                with patch.object(runner, 'discover', return_value=[dict(sample)]), \
                        patch.object(runner, 'command', side_effect=observe):
                    if failure:
                        with self.assertRaisesRegex(RuntimeError, failure):
                            runner.run(folder)
                    else:
                        runner.run(folder)
                report = json.loads((folder/'results.json').read_text())
                self.assertEqual(report['status'], 'failed' if failure else 'checks-passed')
                self.assertEqual(report['completed'], [] if failure else ['registers'])
                self.assertEqual(report['checks'][-1]['exit_code'], 7 if failure else 0)
                self.assertEqual(report['checks'][-1]['log'], str(folder/((failure or 'registers-native')+'.log')))

    def test_regeneration_mismatch_refuses_native_run(self):
        """A generator that exits successfully with wrong bytes cannot pass or rewrite frozen input."""
        sample = dict(binary='ragnarok-memory-probe', suite='pvm_memory_boundary_reference',
                      source='tests/reference/polkavm_memory/src/main.rs',
                      regenerate='pvm-memory-boundary.bin')
        frozen = ROOT/'tests/fixtures/pvm-memory-boundary.bin'
        before = frozen.read_bytes()
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as temporary:
            folder = Path(temporary)
            # Simulate a successful generator returning malformed corpus data.
            def observe(arguments, name, workspace):
                if name.endswith('-reference'):
                    (workspace/sample['regenerate']).write_bytes(b'wrong')
                return dict(command=list(map(str, arguments)), exit_code=0,
                            log=str(workspace/(name+'.log')), elapsed_seconds=0)
            with patch.object(runner, 'discover', return_value=[dict(sample)]), \
                    patch.object(runner, 'command', side_effect=observe):
                with self.assertRaisesRegex(ValueError, 'fixture mismatch'):
                    runner.run(folder)
            report = json.loads((folder/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(len(report['checks']), 2)
            self.assertEqual(report['completed'], [])
        self.assertEqual(frozen.read_bytes(), before)


# Standalone execution runs process/tooling controls only; the Make target owns native comparison.
if __name__ == '__main__':
    unittest.main(verbosity=2)
