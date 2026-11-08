# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prevent incomplete WebSocket observations or unrelated crashes becoming adoption evidence."""
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from websocket_adoption import COMPLETE, PREFIX, classify
import websocket_adoption


class WebSocketAssessment(unittest.TestCase):
    """Keep process failure distinct from witnessed library outcomes and transport qualification."""

    def test_known_close_outcomes(self):
        """Only exact witnessed signal or fully joined cleanup can be classified."""
        self.assertEqual(classify(-signal.SIGPIPE, PREFIX), 'blocked-by-sigpipe')
        self.assertEqual(classify(0, COMPLETE), 'peer-close-retired')

    def test_missing_delivery_or_cleanup_fails(self):
        """Earlier failures and successful exits without complete cleanup are not evidence."""
        for code, output in ((-signal.SIGPIPE, ''), (0, PREFIX),
                             (-signal.SIGPIPE, PREFIX.replace('probe: delivered=7\n', '')),
                             (-signal.SIGPIPE, PREFIX+'unexpected error\n'),
                             (-signal.SIGSEGV, PREFIX), (1, COMPLETE)):
            # Each case represents a different misleading success an assessment must reject.
            with self.subTest(code=code, output=output), self.assertRaises(ValueError):
                classify(code, output)

    def test_configured_listener_requires_clean_retirement(self):
        """SIGPIPE after setting the Darwin listener option is a failed configuration regression."""
        self.assertEqual(classify(0, COMPLETE, require_clean_exit=True), 'peer-close-retired')
        with self.assertRaises(ValueError):
            classify(-signal.SIGPIPE, PREFIX, require_clean_exit=True)

    def test_failed_build_or_timeout_cannot_retain_old_assessment(self):
        """A stale successful report or binary must not survive an incomplete fresh run."""
        for failed_build in (True, False):
            # Both failures happen after retiring old evidence and before writing a new verdict.
            with self.subTest(failed_build=failed_build), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                folder = root/'build/tests/websocket-adoption'
                folder.mkdir(parents=True)
                report = folder/'assessment.json'
                report.write_text('stale assessment')
                checks = Mock()
                checks.build.return_value = ({'exit_code': int(failed_build), 'log': 'build.log'},
                                             folder/'stale-binary')
                checks.command.side_effect = subprocess.TimeoutExpired('slow-peer', 20)
                with patch.object(websocket_adoption, 'ROOT', root), patch.object(
                        websocket_adoption, 'installed', return_value=(root/'compiler', None)), patch.object(
                        websocket_adoption, 'NativeChecks', return_value=checks):
                    with self.assertRaises(RuntimeError if failed_build else subprocess.TimeoutExpired):
                        websocket_adoption.main()
                self.assertFalse(report.exists())
                if failed_build:
                    # A compile refusal cannot launch any preexisting executable.
                    checks.command.assert_not_called()
