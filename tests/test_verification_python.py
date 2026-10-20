# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check fresh Python evidence and rejection of empty discovery.

Exposes VerificationPython for unittest discovery; test methods exercise the stated contracts.
"""
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_python


# Keep python ownership and failure safeguards independent of other verification groups.
class VerificationPython(unittest.TestCase):
    def test_timeout_retains_failed_report_and_partial_progress(self):
        """A discovery deadline must leave fresh failure evidence and identify the active test."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'results.json').write_text(json.dumps(dict(status='checks-passed')))
            timeout = subprocess.TimeoutExpired(['python', 'unittest'], 300,
                                                output=b'test_slow_reference ... ', stderr=b'diagnostic')
            with patch.object(test_python, 'BUILD', folder), patch.object(
                    test_python.NativeChecks, 'command', side_effect=timeout) as command, patch('sys.stdout'):
                with self.assertRaises(SystemExit) as stopped:
                    test_python.main()
            self.assertEqual(stopped.exception.code, 1)
            report = json.loads((folder/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['check']['exit_code'], 124)
            self.assertEqual(command.call_args.kwargs['timeout'], 300)
            self.assertIn('-v', command.call_args.args[0])
            output = (folder/'python-tests.log').read_text()
            self.assertIn('test_slow_reference', output)
            self.assertIn('diagnostic', output)
            self.assertIn('timed out', output)

    # Even a successful unittest exit must not claim coverage when discovery found no tests.
    def test_empty_python_discovery_fails_fresh(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'results.json').write_text(json.dumps(dict(status='checks-passed')))
            result = dict(exit_code=0, command=['fixture'], log='fixture.log',
                          output='Ran 0 tests in 0.001s\n\nOK\n')
            with patch.object(test_python, 'BUILD', folder), patch.object(
                    test_python, 'python_tests', return_value=result), patch('sys.stdout'):
                with self.assertRaises(SystemExit) as stopped:
                    test_python.main()
            self.assertEqual(stopped.exception.code, 1)
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'failed')


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
