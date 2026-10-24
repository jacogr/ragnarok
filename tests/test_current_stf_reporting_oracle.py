# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent guarantee/assurance pipeline invariants with complete input and successor maps."""
import unittest
import current_stf_reporting_oracle as reference
from current_stf_oracle import decode_checkpoint, Reader, history
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class CurrentStfReportingOracle(unittest.TestCase):
    """No native result participates in classification, signing, queueing or statistics expectations."""

    @classmethod
    def setUpClass(cls):
        """Calculate both complete chains once and retain exact report/block/map bytes for separate invariants."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states, cls.children = [], []
        for line in cls.lines:
            if line.startswith('P '):
                cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))]); cls.children.append([])
            elif line.startswith('B '): cls.children[-1].append(bytes.fromhex(line[2:]))
            elif line.startswith('O '): cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))

    def state(self, case, slot):
        """All tested slots advance consecutively from the original slot1 map."""
        return self.states[case][slot-1]

    def test_shuffle_rotation_and_two_or_three_credentials(self):
        """The independent zero-entropy permutation gives distinct groups; previous rotation differs at slot4."""
        self.assertEqual(reference.permutation(bytes(32)), [5, 2, 1, 4, 3, 0])
        first, _ = reference.inputs(self.state(0, 2), 0, 3)
        self.assertEqual([[i for i, _ in item['credentials']] for item in first], [[1, 2], [0, 3]])
        previous, _ = reference.inputs(self.state(1, 3), 1, 4)
        self.assertEqual([item['slot'] for item in previous], [3, 3])
        self.assertEqual([[i for i, _ in item['credentials']] for item in previous], [[1, 2], [0, 3]])
        current, _ = reference.inputs(self.state(1, 8), 1, 9)
        self.assertEqual([len(item['credentials']) for item in current], [3, 3])
        self.assertEqual({i for item in current for i, _ in item['credentials']}, set(range(6)))

    def test_subquorum_then_same_block_release_and_replacement(self):
        """Four votes preserve assignments; five release old reports before replacing both cores with new packages."""
        old = reference.pending(self.state(0, 3)[chapter_key(10)])
        self.assertTrue(all(item is not None and item['registered'] == 3 for item in old))
        self.assertEqual(self.state(0, 4)[chapter_key(10)], self.state(0, 3)[chapter_key(10)])
        after = reference.pending(self.state(0, 5)[chapter_key(10)])
        self.assertTrue(all(item is not None and item['registered'] == 5 for item in after))
        self.assertTrue(all(old[i]['guarantee']['report'] != after[i]['guarantee']['report'] for i in range(2)))
        queued = reference.ready(self.state(0, 5)[chapter_key(14)])[5]
        self.assertEqual([wire for wire, _ in queued], [item['guarantee']['report'] for item in old])
        self.assertEqual([dependencies for _, dependencies in queued], [reference.DEPENDENCY]*2)

    def test_partial_release_timeout_and_zero_bit_assurances(self):
        """Per-core votes do not leak across cores, and expiry clears without creating an available report."""
        after6 = reference.pending(self.state(0, 6)[chapter_key(10)])
        self.assertIsNone(after6[0]); self.assertIsNotNone(after6[1])
        self.assertEqual(self.state(0, 8)[chapter_key(10)], bytes(2))
        self.assertEqual(sum(map(len, reference.ready(self.state(0, 8)[chapter_key(14)]))), 4)
        old = reference.pending(self.state(1, 4)[chapter_key(10)])
        self.assertEqual(reference.pending(self.state(1, 8)[chapter_key(10)]), old)
        new = reference.pending(self.state(1, 9)[chapter_key(10)])
        self.assertTrue(all(item['registered'] == 9 for item in new))
        self.assertEqual(reference.ready(self.state(1, 9)[chapter_key(14)])[9], [])
        self.assertEqual(self.state(1, 11)[chapter_key(10)], self.state(1, 10)[chapter_key(10)])
        before, _ = statistics_parse(self.state(1, 10)[chapter_key(13)], DEFAULT)
        after, _ = statistics_parse(self.state(1, 11)[chapter_key(13)], DEFAULT)
        self.assertEqual([row[5] for row in after[0]], [row[5]+1 for row in before[0]])
        self.assertTrue(all(row[1] == 0 for row in after[2]))

    def test_statistics_distinguish_incoming_and_available_reports(self):
        """Same-block replacement accounts incoming refinement/bundles and old available DA bytes separately."""
        (current, _, cores, services), _ = statistics_parse(self.state(0, 5)[chapter_key(13)], DEFAULT)
        self.assertEqual([row[0] for row in cores], [103+4*4104, 104+5*4104])
        self.assertEqual([row[6] for row in cores], [105, 106])
        self.assertEqual([row[7] for row in cores], [13, 14])
        self.assertEqual([row[1] for row in cores], [5, 5])
        self.assertEqual(services, [(42, 0, 0, 2, 27, 5, 7, 9, 11, 0, 0, 0)])
        prior, _ = statistics_parse(self.state(0, 4)[chapter_key(13)], DEFAULT)
        expected = [1 if i in (0, 1, 2, 3) else 0 for i in range(6)]  # Rotation1 swaps the groups at slot5.
        self.assertEqual([a[4]-b[4] for a, b in zip(current, prior[0])], expected)

    def test_authorization_history_and_unresolved_dependency(self):
        """Pool removal, recent package roots and C14 full reports remain distinct from accumulated history."""
        initial_blocks, _ = history(self.states[0][0][chapter_key(3)])
        self.assertEqual(initial_blocks[0][1], reference.DEPENDENCY+bytes(32))
        after, _ = history(self.state(0, 3)[chapter_key(3)])
        self.assertEqual(len(after[-1][1]), 128)
        source = Reader(self.state(0, 3)[chapter_key(1)])
        self.assertEqual([source.take(32*source.count()) for _ in range(2)], [bytes(64)]*2)
        for chain in self.states:
            for state in chain:
                self.assertEqual(state[chapter_key(15)], bytes(12))
                self.assertEqual(state[chapter_key(16)], b'\0')
                self.assertTrue(all(deps == reference.DEPENDENCY for row in reference.ready(state[chapter_key(14)]) for _, deps in row))

    def test_exact_refusals_and_unchanged_complete_entries(self):
        """Eight contextual failure classes preserve complete canonical parents; no guest or service mutation is implied."""
        self.assertEqual(self.evidence['transitions'], 20)
        self.assertEqual(len(self.evidence['refusals']), 35)
        self.assertEqual(set(self.evidence['refusals']), {'credential/InvalidSignature', 'credential/WrongAssignment',
            'policy/Unauthorized', 'anchor/InvalidRecentAnchor', 'assurance/InvalidSignature',
            'assurance/WrongParent', 'assignment/OccupiedCore', 'availability/UnassignedCore'})
        changed = {chapter_key(i) for i in (1, 3, 6, 10, 11, 13, 14)}
        for chain in self.states:
            for before, after in zip(chain, chain[1:]):
                self.assertEqual(set(before), set(after)); self.assertEqual(len(after), 30)
                self.assertTrue(all(before[key] == after[key] for key in set(before)-changed))
