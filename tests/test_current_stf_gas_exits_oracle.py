# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Cross-phase whole-map checks for gas-limited literal guest outcomes and operand pooling."""
import unittest
import current_stf_gas_exits_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse, DEFAULT
from state_service_values_oracle import key as value_key


class CurrentStfGasExitsOracle(unittest.TestCase):
    """Assertions distinguish actual consumption from declared budgets and successful host checkpoints."""

    @classmethod
    def setUpClass(cls):
        """Retain every independently calculated state in chain/slot order."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states = []
        for line in cls.lines:
            if line.startswith('P '): cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))])
            elif line.startswith('O '): cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))

    def state(self, case, slot):
        """All authored children follow the original slot1 consecutively."""
        return self.states[case][slot-1]

    def test_prepaid_block_and_host_oog_are_distinct(self):
        """An unaffordable block leaves its positive gas unchanged; an underfunded host drains it."""
        self.assertEqual(reference.outcome('create', 1), dict(charge=0, retained=False, exit='basic-block'))
        self.assertEqual(reference.outcome('create', 105), dict(charge=105, retained=False, exit='write'))
        self.assertEqual(reference.outcome('checkpoint-panic', 2753), dict(charge=2753, retained=False, exit='checkpoint'))
        self.assertEqual(reference.outcome('checkpoint-panic', 2754), dict(charge=2754, retained=True, exit='terminal'))

    def test_all_whole_maps_bind_statistics_timestamps_and_implications(self):
        """One operand receives g; two operands receive2g, but run one guest and count both operands."""
        for case, (mode, budget) in enumerate(reference.CASES):
            last = 0
            for slot, count in ((5, 1), (7, 2)):
                expected = reference.outcome(mode, count*budget); state = self.state(case, slot)
                parsed, _ = statistics_parse(state[chapter_key(13)], DEFAULT)
                service = {row[0]: row for row in parsed[3]}[99]
                self.assertEqual(service[9:], (count, 0, expected['charge']))
                last = slot # Nonzero operand count retains this statistics key even when actual gas is zero.
                self.assertEqual(metadata_parse(state[chapter_service(255, 99)], 105)[2][2], last)
                retained = expected['retained']
                output = b'\1'+(99).to_bytes(4, 'little')+reference.pipeline.COMMITMENT if retained else b'\0'
                self.assertEqual(state[chapter_key(16)], output)
                self.assertEqual(state[chapter_key(14)], bytes(12))
            self.assertEqual(metadata_parse(self.state(case, 8)[chapter_service(255, 99)], 105)[2][2], last)

    def test_pooled_budget_crosses_host_and_checkpoint_boundaries(self):
        """A1325-gas operand cannot retain a write, while two can;1377 pooled reaches the exact checkpoint price."""
        self.assertFalse(reference.outcome('create', 1325)['retained'])
        self.assertTrue(reference.outcome('create', 2650)['retained'])
        self.assertFalse(reference.outcome('checkpoint-panic', 1377)['retained'])
        self.assertTrue(reference.outcome('checkpoint-panic', 2754)['retained'])
        for case, (mode, budget) in enumerate(reference.CASES):
            if budget == 1:
                for slot in (5, 7):
                    self.assertEqual(metadata_parse(self.state(case, slot)[chapter_service(255, 99)], 105)[2][2], slot)
        self.assertEqual((self.evidence['transitions'], self.evidence['processed_reports']), (175, 100))
