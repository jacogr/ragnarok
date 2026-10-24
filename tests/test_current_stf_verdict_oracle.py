# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent invariants for verdict thresholds, fault signatures, exact markers and complete-map preservation."""
import copy
import json
import unittest
import current_stf_verdict_oracle as reference
from current_stf_oracle import decode_checkpoint, Reader
from current_stf_epoch_oracle import roster, consensus, NULL_VALIDATOR
from state_layout_oracle import chapter_key, digest
from test_current_stf_population_oracle import marker


class CurrentStfVerdictOracle(unittest.TestCase):
    """Inspect separately calculated protocol invariants without a native backend or observed successor."""

    @classmethod
    def setUpClass(cls):
        """Calculate the frozen request/output corpus once and split its three independently advancing chains."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states, cls.children = [], []
        for line in cls.lines:
            if line.startswith('P '):
                cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))])
                cls.children.append([])
            elif line.startswith('O '):
                cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
            elif line.startswith('B '):
                cls.children[-1].append(bytes.fromhex(line[2:]))
        values = [digest(item['guarantee']['report']) for item in reference.original_assignments()]
        cls.targets = [values[0], values[2], values[1]]

    def test_good_bad_wonky_sets_and_exact_assignment_cancellation(self):
        """New bad/wonky judgments cancel only their assignments; good survives until the exact five-slot timeout."""
        bad, wonky, good = self.targets
        prior, after = self.states[0][:2]
        groups = reference.sets(after[chapter_key(5)])
        self.assertEqual(groups[:3], [[good], sorted([bytes(32), bad]), [wonky]])
        original = reference.assignments(prior[chapter_key(10)])
        self.assertEqual([item is not None for item in original], [True, True, False])
        self.assertEqual(reference.assignments(after[chapter_key(10)]), [None, original[1], None])
        self.assertEqual(self.states[0][2][chapter_key(10)], after[chapter_key(10)])
        self.assertEqual(self.states[0][3][chapter_key(10)], bytes(3))  # Slot6 = registered1 + five.

    def test_wonky_cancellation_on_an_active_core(self):
        """A separate branch assigns wonky to core0 and keeps good core1 byte-identical."""
        before, after = self.states[2]
        original = reference.assignments(before[chapter_key(10)])
        report_hash = digest(original[0]['guarantee']['report'])
        self.assertIn(report_hash, reference.sets(after[chapter_key(5)])[2])
        self.assertEqual(reference.assignments(after[chapter_key(10)]), [None, original[1], None])
        self.assertEqual(len(roster(before[chapter_key(8)]))//3, 2)

    def test_marker_repeats_union_once_and_filters_only_on_crossing(self):
        """Culprit-then-fault order retains scalar6 twice; C5 union has it once and nullifies its full staging record."""
        state = self.states[0][1]
        key6 = reference.signed(6, b'jam_valid', bytes(32))[0]
        key7 = reference.signed(7, b'jam_valid', bytes(32))[0]
        expected_marker = [key6]+sorted([key6, key7])
        self.assertEqual(marker(self.children[0][0])[3], expected_marker)
        self.assertEqual(expected_marker.count(key6), 2)
        self.assertEqual(reference.sets(state[chapter_key(5)])[3], sorted([key6, key7]))
        self.assertEqual(len(reference.sets(self.states[0][2][chapter_key(5)])[3]), 3)
        for at, slot in enumerate(reference.SLOTS[0]):
            pending = consensus(self.states[0][at+1][chapter_key(4)])[0]
            self.assertEqual(NULL_VALIDATOR in pending, slot >= 12)
            if slot >= 12:
                self.assertEqual(pending[0], NULL_VALIDATOR)
        self.assertTrue(all(state[chapter_key(7)] == self.states[0][0][chapter_key(7)] for state in self.states[0]))

    def test_parent_current_previous_and_crossing_quorums(self):
        """Epoch boundaries use the original parent's roster, with independently sized5/7-vote thresholds."""
        targets = self.targets
        for at, slot in enumerate(reference.SLOTS[1]):
            before, after = self.states[1][at:at+2]
            value = reference.positive(before, 1, slot, targets)
            epoch = int.from_bytes(before[chapter_key(11)], 'little')//12
            for verdict in value['verdicts']:
                members = roster(before[chapter_key(8 if verdict['age'] == epoch else 9)])
                self.assertEqual(len(verdict['votes']), 2*len(members)//3+1)
                self.assertEqual(verdict['votes'][-1]['index'], len(members)-1)
            if slot == 12:
                self.assertEqual((len(value['verdicts'][0]['votes']), len(roster(after[chapter_key(8)]))), (5, 9))
            elif slot == 13:
                self.assertEqual(sorted(len(v['votes']) for v in value['verdicts']), [5, 7, 7])
            elif slot == 14:
                self.assertEqual(sorted(len(v['votes']) for v in value['verdicts']), [5, 7])
            elif slot == 24:
                self.assertEqual((len(value['verdicts'][0]['votes']), len(roster(after[chapter_key(8)]))), (7, 6))

    def test_fault_domains_opposition_and_previous_roster_eligibility(self):
        """Faults use judgment validity domains, and previous-only keys can submit delayed contrary evidence."""
        parent = self.states[0][0]
        value = reference.positive(parent, 0, 2, self.targets)
        key7 = reference.signed(7, b'jam_valid', bytes(32))[0]
        self.assertNotIn(key7, [row[32:64] for row in roster(parent[chapter_key(8)])])
        self.assertIn(key7, [row[32:64] for row in roster(parent[chapter_key(9)])])
        good_fault = next(item for item in value['faults'] if item['target'] == self.targets[2])
        self.assertFalse(good_fault['vote'])
        self.assertEqual(good_fault['signature'], reference.signed(6, b'jam_invalid', self.targets[2])[1])
        changed = copy.deepcopy(value)
        item = next(item for item in changed['faults'] if item['target'] == self.targets[2])
        item['signature'] = reference.signed(6, b'$jam_invalid', self.targets[2])[1]
        with self.assertRaisesRegex(AssertionError, '^InvalidSignature$'):
            reference.plan(parent, changed)

    def test_late_controls_and_complete_unchanged_entries(self):
        """Typed failures cover actual late evidence/marker checks, while every other key remains in each expected map."""
        self.assertEqual(self.evidence['transitions'], 12)
        self.assertEqual(len(self.evidence['refusals']), 20)
        self.assertEqual(set(self.evidence['refusals']), {'InvalidQuorum', 'InvalidEpoch', 'InvalidSignature',
                         'InvalidSplit', 'MissingFault', 'InvalidEvidence', 'InvalidMarker', 'AlreadyJudged', 'InvalidKey'})
        self.assertEqual(sum(line.startswith('N ') for line in self.lines), 20)
        changed = {chapter_key(i) for i in (1, 3, 4, 5, 6, 8, 9, 10, 11, 13)}
        for chain in self.states:
            for before, after in zip(chain, chain[1:]):
                self.assertEqual(set(before), set(after))
                self.assertEqual(len(after), 30)
                self.assertTrue(all(before[key] == after[key] for key in set(before)-changed))
                self.assertEqual(after[chapter_key(13)][-25:], bytes(25))  # Three empty core rows and empty service dictionary.
