# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent epoch reporting invariants distinguish roster roles and pre-rollover assurance counters."""
import unittest
from scenario_states import checkpoint_states
import current_stf_epoch_reporting_oracle as reference
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class EpochReportingOracleTests(unittest.TestCase):
    """Inspect independently calculated complete successors without native observed input."""

    @classmethod
    def setUpClass(cls):
        """Retain the two chains and immutable frozen identities once for all equation checks."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states = checkpoint_states(cls.lines)

    def test_prior_and_posterior_credentials_select_distinct_keys(self):
        """Current versus previous guarantees at12 select different roster order and historical entropy."""
        parent = self.states[0][11]
        current, _ = reference.credentials(parent, 12, 12)
        previous, _ = reference.credentials(parent, 12, 11)
        self.assertEqual(current, reference.epoch.consensus(parent[chapter_key(4)])[0])
        self.assertEqual(previous, reference.epoch.roster(parent[chapter_key(8)]))
        self.assertNotEqual(current, previous)
        self.assertNotEqual(parent[chapter_key(6)][32:64], parent[chapter_key(6)][64:96])
        for state in self.states:
            before = state[11]
            for stamp in (11, 12):
                item = reference.guarantee(before, 0, 12, 12, stamp)
                reference.validate(before, 12, [item], reference.assurances(before, 5, 3))

    def test_assurances_are_accounted_before_statistics_rollover(self):
        """Five boundary assurances extend the previous counters, while current assurance counters reset."""
        for case, states in enumerate(self.states):
            before, _ = statistics_parse(states[11][chapter_key(13)], DEFAULT)
            after, _ = statistics_parse(states[12][chapter_key(13)], DEFAULT)
            self.assertEqual([r[5] for r in after[1]], [r[5]+(i < 5) for i, r in enumerate(before[0])])
            self.assertEqual([r[5] for r in after[0]], [0]*6)
            self.assertEqual(sum(r[0] for r in after[0]), 1)
            self.assertEqual(sum(r[4] for r in after[0]), 4)
            roster, _ = reference.credentials(states[11], 12, 12 if case == 0 else 11)
            guaranteed, _ = reference.inputs(states[11], case, 12)
            keys = {roster[i][32:64] for item in guaranteed for i, _ in item['credentials']}
            active = reference.epoch.roster(states[12][chapter_key(8)])
            self.assertEqual([r[4] for r in after[0]], [int(r[32:64] in keys) for r in active])

    def test_boundary_subquorum_release_replacement_and_dependencies(self):
        """Four votes retain old assignments; five boundary votes queue old reports before installing both replacements."""
        for states in self.states:
            self.assertEqual(states[10][chapter_key(10)], states[11][chapter_key(10)])
            old = reference.reporting.pending(states[11][chapter_key(10)])
            new = reference.reporting.pending(states[12][chapter_key(10)])
            self.assertTrue(all(item['registered'] == 12 for item in new))
            queued = reference.reporting.ready(states[12][chapter_key(14)])[0]
            self.assertEqual([wire for wire, _ in queued], [item['guarantee']['report'] for item in old])
            self.assertEqual([deps for _, deps in queued], [reference.reporting.DEPENDENCY]*2)
            self.assertEqual(states[12][chapter_key(10)], states[13][chapter_key(10)])
            self.assertEqual(states[14][chapter_key(10)], bytes(2))
            self.assertEqual(states[17][chapter_key(10)], bytes(2))

    def test_complete_mapping_preservation_and_exact_refusals(self):
        """Only declared global chapters change; every service value remains exact, including present-empty entries."""
        self.assertEqual(self.evidence['transitions'], 18)
        self.assertEqual(len(self.evidence['refusals']), 28)
        self.assertEqual(set(self.evidence['refusals']), {'credential/InvalidSignature', 'credential/WrongAssignment', 'credential/InvalidSlot', 'assurance/InvalidSignature'})
        mutable = {chapter_key(i) for i in (1, 3, 4, 6, 8, 9, 10, 11, 13, 14)}
        for states in self.states:
            original = states[1]
            for state in states.values():
                self.assertEqual(set(state), set(original)); self.assertEqual(len(state), 30)
                self.assertTrue(all(state[key] == original[key] for key in set(original)-mutable))
