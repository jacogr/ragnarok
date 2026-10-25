# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exact independently authored fuzz seed pairs do not imply matching header/state clocks."""
import unittest
from types import SimpleNamespace
import jam_fuzzer_seed_guests_oracle as reference
from jam_fuzzer_guest_reference import replay


class SeedGuestReference(unittest.TestCase):
    """Retain complete independently calculated guest maps and explicit seed headers."""

    def test_exact_seed_pairs(self):
        """Five mismatched-clock seeds execute20 real guest invocations across ten complete successors."""
        requests, lines, evidence = replay(reference, headers=True)
        self.assertEqual(evidence['reference']['header_slot'], 0)
        self.assertEqual(evidence['reference']['state_slot'], 1)
        self.assertEqual(evidence['reference']['guest_executions'], 20)
        self.assertEqual(sum(line.startswith('O ') for line in lines), 10)
        self.assertEqual(sum(line.startswith('H ') for line in requests), 5)
        for line in requests:
            if line.startswith('H '):
                self.assertEqual(bytes.fromhex(line[2:])[96:100], bytes(4))

    def test_dangling_header_is_refused(self):
        """A header cannot silently replace an initialized map or be left without its exact complete seed."""
        for lines in (['H aa'], ['P aa', 'B bb', 'O cc', 'H dd'],
                      ['H aa', 'H bb', 'P cc', 'B dd', 'O ee']):
            source = SimpleNamespace(expected_observations=lambda rows=lines: ([], rows, {}))
            with self.assertRaises(AssertionError):
                replay(source, headers=True)
