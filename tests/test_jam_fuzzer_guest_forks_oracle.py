# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Counterfactual guest siblings have independently calculated whole-map answers."""
import unittest
from jam_fuzzer_guest_forks_oracle import expected_observations
from jam_fuzzer_guest_reference import replay
import jam_fuzzer_guest_forks_oracle as reference


class GuestForkReference(unittest.TestCase):
    """Freeze meaningful guest mutations and preserve exact original-last ordering."""

    def test_guest_siblings(self):
        """All five guest exit/effect modes retain separate sibling roots and complete original continuations."""
        _, lines, evidence = expected_observations()
        requests, expected, _ = replay(reference, forks=True)
        self.assertEqual(lines, expected)
        self.assertEqual(evidence['transitions'], 50)
        self.assertEqual(evidence['nonempty_guest_siblings'], 15)
        self.assertEqual(sum(line.startswith('V ') for line in requests), 15)
        self.assertEqual(sum(line.startswith('O ') for line in lines), 50)
        for index, line in enumerate(lines):
            if line.startswith('V '):
                self.assertTrue(lines[index+2].startswith('B '))
                self.assertNotEqual(lines[index+1], lines[index+3])
