# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full600-entry winner permutation checks preserve identifier/attempt pairs and exact epoch scope."""
import unittest
from jam_fuzzer_full_sealing_oracle import zigzag,PLANS


class FullWinnerPermutation(unittest.TestCase):
    """The full permutation has independent endpoint, uniqueness and attempt-retention witnesses."""

    def test_full_outside_in_order(self):
        """Every original identifier appears once, with its attempt byte attached, including both middle entries."""
        entries = [index.to_bytes(32,'big')+bytes([index % 2]) for index in range(600)]
        result = zigzag(entries)
        self.assertEqual(result[:4],[entries[0],entries[599],entries[1],entries[598]])
        self.assertEqual(result[-2:],[entries[299],entries[300]])
        self.assertEqual(set(result),set(entries))
        self.assertEqual(len(result),len(set(result)))

    def test_only_complete_full_contest_can_select_winners(self):
        """A599-entry contest cannot be treated as complete; ordinary and skipped paths have explicit distinct slot plans."""
        with self.assertRaises(AssertionError): zigzag([bytes(33)]*599)
        with self.assertRaises(AssertionError): zigzag([bytes(33)]*601)
        self.assertIn((600,(499,600,601)),PLANS)
        self.assertIn((600,(499,500,1200,1201)),PLANS)
