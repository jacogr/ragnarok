# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Require complete instruction counters, calibrated scope exclusion and stale-report retirement."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from pvm_instruction_profile import profile_counts, calibration_passed, run


def profile(total=42, function='pvm_profile_selected'):
    """Author the documented raw format independently of the profiler runner."""
    return '# callgrind format\nversion: 1\nevents: Ir Bc Bcm Bi Bim\nfn='+function+'\n1 1 0 0 0 0\ntotals: '+str(total)+' 0 0 0 0\n'


class InstructionProfileTests(unittest.TestCase):
    """Partial files and arbitrary process success cannot certify selected execution."""

    def test_complete_and_empty_counters(self):
        """Keep every event and accept zero only for the deliberately absent-scope control."""
        self.assertEqual(profile_counts(profile()), dict(Ir=42, Bc=0, Bcm=0, Bi=0, Bim=0))
        self.assertEqual(profile_counts(profile(0), allow_empty=True)['Ir'], 0)
        with self.assertRaises(ValueError):
            profile_counts(profile(0))

    def test_bad_counters(self):
        """Reject missing/duplicate/truncated/malformed/negative totals and shifted event columns."""
        valid = profile()
        for text in [valid.replace('totals:', 'partial:'), valid+valid, valid.replace('42 0', '-1 0'),
                valid.replace('42 0', '01 0'), valid.replace('42 0', '42.0 0'),
                valid.replace('Ir Bc', 'Bc Ir'), valid.replace('Ir Bc', 'Ir Ir'),
                valid.replace('42 0 0 0 0', '42 0'), valid.replace('# callgrind format', '# other')]:
            # Every broken file retains the other control fields, isolating its own refusal condition.
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    profile_counts(text)

    def test_selected_and_excluded_scopes(self):
        """Both the selected and deliberately absent function need classified positive process output."""
        good = dict(exit_code=0, output='PVM profile calibration passed\n')
        self.assertTrue(calibration_passed(good, profile(), True))
        self.assertTrue(calibration_passed(good, profile(0), False))
        for result, text, selected in [(dict(exit_code=1, output=good['output']), profile(), True),
                (dict(exit_code=0, output='generic success'), profile(), True),
                (good, profile(function='other'), True), (good, profile()+'fn=pvm_profile_outside\n', True),
                (good, profile(0), True), (good, profile(), False)]:
            # Generic crashes, wrong scopes and whole-process collection are never a calibration fallback.
            self.assertFalse(calibration_passed(result, text, selected))

    def test_refusal_retires_completed_reports(self):
        """An unsupported local host cannot leave an old successful aggregate available."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for name in ('results.json', 'summary.md'):
                (folder/name).write_text('stale success')
            with patch('pvm_instruction_profile.BUILD', folder), patch(
                    'pvm_instruction_profile.platform.system', return_value='unsupported'):
                with self.assertRaises(RuntimeError):
                    run()
            self.assertFalse((folder/'results.json').exists())
            self.assertFalse((folder/'summary.md').exists())
            self.assertIn('failed', (folder/'partial.json').read_text())
