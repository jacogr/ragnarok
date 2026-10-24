# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Calibrated sanitizer verdicts reject generic failures, missing instrumentation and partial corpus output."""
import sys
import unittest
import tempfile
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_sanitizers import calibration_passed, suite_passed, main


class PvmSanitizerTests(unittest.TestCase):
    """Only an exact positive control and classified instrumented reads establish the analyzer profile."""

    def test_positive_control(self):
        """A matching success line with nonzero status or extra diagnostics cannot calibrate ASan."""
        self.assertTrue(calibration_passed('positive', dict(exit_code=0, output='PVM sanitizer positive passed\n')))
        self.assertFalse(calibration_passed('positive', dict(exit_code=1, output='PVM sanitizer positive passed\n')))
        self.assertFalse(calibration_passed('positive', dict(exit_code=0, output='AddressSanitizer disabled\n')))

    def test_negative_controls(self):
        """Each intended class and raw one-byte read site must be present; crashes alone are insufficient."""
        for mode, reason in [('heap', 'heap-use-after-free'), ('stack', 'stack-buffer-overflow')]:
            output = 'ERROR: AddressSanitizer: '+reason+'\nREAD of size 1\npvm_sanitizer_read'
            self.assertTrue(calibration_passed(mode, dict(exit_code=1, output=output)))
            for code, text in [(0, output), (1, 'Segmentation fault'), (1, output.replace(reason, 'wrong-class')),
                               (1, output.replace('pvm_sanitizer_read', 'unrelated_read'))]:
                # The positive classified row remains otherwise identical in each corrupt control.
                self.assertFalse(calibration_passed(mode, dict(exit_code=code, output=text)))

    def test_corpus_output(self):
        """Preserve complete golden output and reject a sanitizer report even if process status says success."""
        expected = 'first\nsecond\n'
        self.assertTrue(suite_passed(dict(exit_code=0, output=expected), expected))
        for code, text in [(1, expected), (0, 'first\n'), (0, expected+'AddressSanitizer: failure\n')]:
            self.assertFalse(suite_passed(dict(exit_code=code, output=text), expected))

    def test_refusal_retires_stale_report(self):
        """An unsupported analyzer profile cannot leave a previous successful verdict usable."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root/'build/tests/pvm-asan/results.json'
            report.parent.mkdir(parents=True)
            report.write_text('{"stale":true}')
            with patch('pvm_sanitizers.ROOT', root), patch('pvm_sanitizers.platform.system', return_value='unsupported'):
                with self.assertRaises(RuntimeError):
                    main()
            self.assertFalse(report.exists())
