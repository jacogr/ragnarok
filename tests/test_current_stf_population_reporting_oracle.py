# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent population/reporting invariants for prior quorum, resize clearing and roster-key attribution."""
import unittest
import current_stf_population_reporting_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse, DEFAULT


def statistics(state):
    """Decode each statistics array using its actual separately counted current/previous roster."""
    current = len(reference.epoch.roster(state[chapter_key(8)]))
    previous = len(reference.epoch.roster(state[chapter_key(9)]))
    parsed, _ = statistics_parse(state[chapter_key(13)], (3, current, previous, *DEFAULT[3:]))
    return parsed


class PopulationReportingOracleTests(unittest.TestCase):
    """All inputs are independent frozen equations; production output never supplies an expected state."""

    @classmethod
    def setUpClass(cls):
        """Retain complete independently generated chains once for separate mathematical assertions."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states = []
        for line in cls.lines:
            if line.startswith('P '): cls.states.append({1: decode_checkpoint(bytes.fromhex(line[2:]))})
            elif line.startswith('O '):
                state = decode_checkpoint(bytes.fromhex(line[2:]))
                cls.states[-1][int.from_bytes(state[chapter_key(11)], 'little')] = state

    def test_populations_and_statistics_resize_independently(self):
        """The fixed capacity9/cores3 does not replace the actual6/9/6 active populations or6/9 previous rows."""
        for states in self.states:
            for slot, active, previous in ((1, 6, 9), (11, 6, 9), (12, 9, 6), (23, 9, 6), (24, 6, 9)):
                self.assertEqual(len(reference.epoch.roster(states[slot][chapter_key(8)])), active)
                self.assertEqual(len(reference.epoch.roster(states[slot][chapter_key(9)])), previous)
                current_rows, previous_rows, cores, _ = statistics(states[slot])
                self.assertEqual((len(current_rows), len(previous_rows), len(cores)), (active, previous, 3))

    def test_quorum_uses_prior_population_before_rollover(self):
        """Five of6 release on growth, seven of9 on shrink; exact two-thirds do not become available."""
        for case, states in enumerate(self.states):
            for before_slot, slot, votes in ((11, 12, 5 if case == 0 else 4), (23, 24, 7 if case == 0 else 6)):
                before = statistics(states[before_slot])
                after = statistics(states[slot])
                self.assertEqual([r[5] for r in after[1]], [r[5]+int(i < votes) for i, r in enumerate(before[0])])
                self.assertEqual([r[5] for r in after[0]], [0]*len(after[0]))
            self.assertEqual(states[12][chapter_key(10)], states[13][chapter_key(10)])
            self.assertEqual([r[1] for r in statistics(states[13])[2]], [6]*3)
            self.assertEqual(states[14][chapter_key(10)], bytes(3))

    def test_resize_clears_without_availability_and_permits_replacement(self):
        """Both resize paths remove old records; only genuine prior quorum puts their reports into the ready ring."""
        for case, states in enumerate(self.states):
            for before_slot, slot, present in ((11, 12, 3), (23, 24, 2)):
                old = reference.reporting.pending(states[before_slot][chapter_key(10)], 3, 9)
                new = reference.reporting.pending(states[slot][chapter_key(10)], 3, 9)
                self.assertEqual(sum(item is not None for item in new), present)
                self.assertTrue(all(item is None or item['registered'] == slot for item in new))
                ready = reference.reporting.ready(states[slot][chapter_key(14)], 3)[slot % 12]
                expected = [item['guarantee']['report'] for item in old if item is not None] if case == 0 else []
                self.assertEqual([wire for wire, _ in ready], expected)
                old_wires = {item['guarantee']['report'] for item in old if item is not None}
                self.assertTrue(all(item is None or item['guarantee']['report'] not in old_wires for item in new))

    def test_erasure_population_and_previous_credential_index_domains(self):
        """Previous6 credentials at growth still declare9 shards; previous9 indices at shrink coexist with6 shards."""
        states = self.states[1]
        for before_slot, slot, shards, selected_count in ((11, 12, 9, 6), (23, 24, 6, 9)):
            gs, _ = reference.inputs(states[before_slot], 1, slot)
            previous = gs[:2]
            self.assertTrue(all(item['slot'] == slot-1 for item in previous))
            for item in previous:
                roster, _ = reference.epoch_reporting.credentials(states[before_slot], slot, item['slot'])
                self.assertEqual(len(roster), selected_count)
                self.assertEqual(int.from_bytes(item['layout']['header'][68:70], 'little'), shards)
            if slot == 24:
                self.assertTrue(any(index >= 6 for item in previous for index, _ in item['credentials']))
            else:
                self.assertEqual(gs[2]['slot'], 12)

    def test_reporter_statistics_match_keys_in_posterior_order(self):
        """Reporter counters follow surviving keys; neither the prior credential index nor nonmember keys count."""
        for case, states in enumerate(self.states):
            for before_slot, slot in ((11, 12), (23, 24)):
                guaranteed, _ = reference.inputs(states[before_slot], case, slot)
                keys = set()
                for item in guaranteed:
                    roster, _ = reference.epoch_reporting.credentials(states[before_slot], slot, item['slot'])
                    keys.update(roster[i][32:64] for i, _ in item['credentials'])
                active = reference.epoch.roster(states[slot][chapter_key(8)])
                self.assertEqual([r[4] for r in statistics(states[slot])[0]], [int(row[32:64] in keys) for row in active])

    def test_three_core_release_preserves_actual_unresolved_prerequisites(self):
        """Each later available report queues its actual recent prerequisite, including dependencies different from the original sentinel."""
        observed = set()
        for states in self.states:
            ready = reference.reporting.ready(states[14][chapter_key(14)], 3)[2]
            self.assertEqual(len(ready), 3)
            for wire, dependencies in ready:
                self.assertEqual(wire[272], 1)
                self.assertEqual(dependencies, wire[273:305]); observed.add(dependencies)
            self.assertEqual(states[25][chapter_key(10)], bytes(3))
        self.assertTrue(any(value != reference.reporting.DEPENDENCY for value in observed))

    def test_exact_refusals_and_complete_service_preservation(self):
        """Only declared global chapters change, and all twelve exact refusals retain independent classification."""
        self.assertEqual(self.evidence['transitions'], 20)
        self.assertEqual(len(self.evidence['refusals']), 12)
        self.assertEqual(set(self.evidence['refusals']), {'credential/WrongErasureShards', 'assurance/InvalidSignature', 'credential/InvalidIndex', 'credential/InactiveCore'})
        mutable = {chapter_key(i) for i in (1, 3, 4, 6, 8, 9, 10, 11, 13, 14)}
        for states in self.states:
            source = states[1]
            for state in states.values():
                self.assertEqual(set(state), set(source)); self.assertEqual(len(state), 30)
                self.assertTrue(all(state[key] == source[key] for key in set(source)-mutable))
                self.assertEqual(state[chapter_key(15)], bytes(12))
                self.assertEqual(state[chapter_key(16)], b'\0')
