# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map STF answers become exact fuzz inputs without native-output feedback."""
from types import SimpleNamespace
import unittest
from jam_fuzzer_guest_reference import replay
import current_stf_report_guests_oracle as guests


class FuzzerGuestReference(unittest.TestCase):
    """Check complete ordered replay, frozen guest evidence and strict refusal of unsupported observations."""

    def test_nonempty_guest_stream(self):
        """Five existing frozen modes cover real report-driven guests and every complete successor map."""
        requests, expected, evidence = replay(guests)
        self.assertEqual(evidence['reference']['guest_executions'], 15)
        self.assertEqual(evidence['reference']['transitions'], 35)
        self.assertEqual(sum(line.startswith('C ') for line in requests), 5)
        self.assertEqual(sum(line.startswith('B ') for line in requests), 35)
        self.assertEqual(sum(line.startswith('O ') for line in expected), 35)
        self.assertEqual([line[2:] for line in requests if line.startswith('C ')],
                         [line[2:] for line in expected if line.startswith('P ')])

    def test_partial_or_substituted_stream_is_refused(self):
        """An incomplete or disconnected map cannot silently become a successful replay request."""
        for lines in ([], ['P aa'], ['B aa', 'O bb'], ['P aa', 'B bb'], ['P aa', 'N ignored'], ['P aa', 'O bb']):
            source = SimpleNamespace(expected_observations=lambda rows=lines: ([], rows, {}))
            with self.assertRaises(AssertionError):
                replay(source)
