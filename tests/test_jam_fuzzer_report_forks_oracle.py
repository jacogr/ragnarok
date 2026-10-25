# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Nonempty guarantee mutations have separate independently calculated complete maps."""
import unittest
from jam_fuzzer_report_forks_oracle import expected_observations


class FuzzerReportForkReference(unittest.TestCase):
    """Freeze original-last selection and whole-map differences before the native backend executes."""

    def test_frozen_forks(self):
        """Four report variants precede their original blocks across two independent reporting chains."""
        requests, lines, evidence = expected_observations()
        self.assertEqual(evidence['successful_imports'], 24)
        self.assertEqual(evidence['nonempty_siblings'], 4)
        self.assertEqual(sum(request.startswith('V ') for request in requests), 4)
        self.assertEqual(sum(line.startswith('O ') for line in lines), 24)
        at = 0
        for request in requests:
            if request.startswith('C ') or request.startswith('N '):
                at += 1
            else:
                if request.startswith('V '):
                    self.assertNotEqual(lines[at+1], lines[at+3])
                at += 2
        self.assertEqual(at, len(lines))
