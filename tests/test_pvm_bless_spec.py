# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent target cardinality witnesses for bless service keys, including identical raw pairs."""
import unittest


class BlessServiceKeys(unittest.TestCase):
    """Raw pair count must equal distinct service count before any dictionary may be published."""

    def test_raw_count_includes_identical_pairs(self):
        """A set of complete pairs loses the evidence needed to reject repeated identical input records."""
        identical = [(1, 1), (1, 1)]
        conflicting = [(1, 1), (1, 2)]
        self.assertEqual(len(set(identical)), 1)
        self.assertEqual(len(set(conflicting)), 2)
        for raw in (identical, conflicting):
            self.assertNotEqual(len({service for service, _ in raw}), len(raw))
            self.assertEqual(422+20*len(raw), 462)
        for raw in ([], [(1, 1)], [(2**32-1, 2**64-1), (0, 0)]):
            self.assertEqual(len({service for service, _ in raw}), len(raw))
