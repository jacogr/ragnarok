# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Require real fatal native traces and isolated limits before admitting Linux diagnostic evidence."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import storage_abort_diagnostics as diagnostic

TRACE = '''Process 17 stopped
* thread #1, stop reason = signal SIGABRT
(lldb) thread backtrace --count 64
  * frame #0: 0x123 libc.so.6`kill + 1
    frame #1: 0x456 symbols-native`cAbort + 2
    frame #2: 0x789 symbols-native`raiseOutOfMem + 3
(lldb) continue
Process 17 exited with status = 6 (0x00000006)
'''


class AbortDiagnosticTests(unittest.TestCase):
    """A successful debugger command alone cannot establish native failure or allocation cause."""

    def test_trace_requires_actual_stop_frames_and_signal(self):
        """Each missing native event invalidates an otherwise plausible debugger transcript."""
        self.assertEqual(len(diagnostic.validate_trace(TRACE)), 3)
        for old, new in (
                ('stop reason = signal SIGABRT', 'stop reason = signal SIGSEGV'),
                ('symbols-native`', 'python3`'),
                ('frame #', 'other #'),
                ('exited with status = 6 (0x00000006)', 'exited with status = 0 (0x00000000)')):
            with self.subTest(event=old), self.assertRaises(ValueError):
                diagnostic.validate_trace(TRACE.replace(old, new))

    def test_trace_does_not_infer_oom(self):
        """Another abort caller is still capturable; source inspection must classify the cause."""
        frames = diagnostic.validate_trace(TRACE.replace('raiseOutOfMem', 'assertionFailure'))
        self.assertIn('assertionFailure', frames[2])

    def test_debugger_wraps_existing_child_only_launcher(self):
        """Only the inferior receives the finite ceiling, with explicit root and fixed workload."""
        argv = diagnostic.debugger_command('/usr/bin/lldb', '/tmp/native with space',
                                           '/tmp/receipt', 'journal', '/tmp/owned', 'a'*64)
        separator = argv.index('--')
        self.assertEqual(argv[separator+1:], [sys.executable, str(diagnostic.EXEC),
                         '/tmp/receipt', str(128*1024*1024), '--', '/tmp/native with space',
                         'open', 'journal', '131072', '/tmp/owned', 'a'*64])
        self.assertIn('settings set target.disable-aslr false', argv)
        self.assertIn('settings set target.process.stop-on-exec false', argv)
        self.assertIn('process handle SIGABRT --stop true --notify true --pass true', argv)
        trace_index = argv.index('thread backtrace --count 64')
        self.assertEqual(argv[trace_index-1], '-k')
        self.assertEqual(argv[separator-2:separator], ['-k', 'continue'])

    def test_unsupported_host_retires_old_success(self):
        """Darwin must fail explicitly before any setup or debugger work and retain a failure receipt."""
        with tempfile.TemporaryDirectory() as owned:
            folder = Path(owned)
            (folder/'summary.md').write_text('stale success')
            (folder/'results.json').write_text('{}')
            with patch.object(diagnostic.platform, 'system', return_value='Darwin'), \
                    patch.object(diagnostic, 'ceilings') as panel, self.assertRaises(RuntimeError):
                diagnostic.run(folder)
            panel.assert_not_called()
            self.assertFalse((folder/'summary.md').exists())
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'failed')

    def test_missing_debugger_is_not_unavailable_success(self):
        """Linux ptrace prerequisites are required, rather than silently skipping the diagnosis."""
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(diagnostic.platform, 'system', return_value='Linux'), \
                patch.object(diagnostic.shutil, 'which', return_value=None), \
                patch.object(diagnostic, 'ceilings') as panel, self.assertRaises(RuntimeError):
            diagnostic.run(folder)
        panel.assert_not_called()
