# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent offender eligibility and exact marker equations preserve cross-section repetition and prior state."""
import unittest
import jam_fuzzer_full_offenders_oracle as reference
from state_layout_oracle import chapter_key


class FullOffenderEvidence(unittest.TestCase):
    """Evidence uses original eligibility; markers are sequences and persistent judgments are sets."""

    @classmethod
    def setUpClass(cls):
        """Own one independently authored full seed; every planner call decodes its own complete judgment sets."""
        cls.parent = reference.original()

    def test_cross_section_repetition_and_prior_retention(self):
        """The same newly offending key can appear twice in the marker but only once in the persistent set."""
        value = reference.payload(culprits=[reference.culprit(1022)],faults=[reference.fault(1022,reference.BAD,True)])
        after,marks = reference.plan(self.parent,value)
        self.assertEqual(len(marks),2)
        self.assertEqual(marks[0],marks[1])
        self.assertEqual(len(reference.judgments(after)[3]),2)
        with self.assertRaisesRegex(AssertionError,'InvalidMarker'): reference.plan(self.parent,value,list(set(marks)))
        self.assertEqual(len(reference.judgments(self.parent[chapter_key(5)])[3]),1)

    def test_preexisting_offender_is_ineligible(self):
        """An otherwise valid independent signature cannot restore an already excluded key's evidence eligibility."""
        with self.assertRaisesRegex(AssertionError,'InvalidKey'):
            reference.plan(self.parent,reference.payload(culprits=[reference.culprit(7)]))

    def test_opposing_evidence_uses_exact_classification(self):
        """A genuine valid-vote signature about a good report is not opposing evidence against that judgment."""
        with self.assertRaisesRegex(AssertionError,'InvalidEvidence'):
            reference.plan(self.parent,reference.payload(faults=[reference.fault(511,reference.GOOD,True)]))
