# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Whole-map expiry order, skipped-time row clearing and block-count history invariants."""
import json
import unittest
import current_stf_ready_expiry_oracle as reference
from current_stf_oracle import decode_checkpoint
from current_stf_reporting_oracle import ready
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class CurrentStfReadyExpiryOracle(unittest.TestCase):
    """Actual processed prefixes and elapsed slots determine independent posterior maps."""

    @classmethod
    def setUpClass(cls):
        """Retain complete states indexed by their explicit slot, not by child count across gaps."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations(); cls.states = []
        for line in cls.lines:
            if line.startswith('P ') or line.startswith('O '):
                state = decode_checkpoint(bytes.fromhex(line[2:]))
                if line.startswith('P '): cls.states.append({})
                cls.states[-1][int.from_bytes(state[chapter_key(11)], 'little')] = state

    def trace(self, case, slot):
        """Inspect only the explicitly independently calculated processing/expiry trace."""
        return next(row for row in self.evidence['traces'][case] if row['slot'] == slot)

    def test_genuine_prefix_matches_earlier_epoch_drain_inputs(self):
        """Every schedule shares the same reachable admission prefix through11 with the earlier frozen fixture."""
        fixture = json.loads(reference.epoch_drain.FIXTURE.read_text())
        for case, (mode, _) in enumerate(reference.CASES):
            self.assertEqual(self.evidence['roots'][case][:10], fixture['successor_roots'][reference.epoch_drain.waves.pipeline.MODES.index(mode)][:10])

    def test_affordable_report_executes_on_its_expiring_row(self):
        """B runs at20 before row8 clearing; C,D,E then run on their own current rows21..23."""
        package = reference.epoch_drain.waves.package
        for case in range(0, 15, 3):
            for slot, name in zip(range(20, 24), 'BCDE'):
                trace = self.trace(case, slot)
                self.assertEqual(trace['processed'], [package(name).hex()]); self.assertEqual(trace['expired'], [])
            self.assertEqual(self.states[case][24][chapter_key(14)], bytes(12))

    def test_past_expiry_drops_unprocessed_dependency_and_stalls_dependants(self):
        """B runs at21; C is eligible but unaffordable and expires, so D and E never invent completion."""
        package = reference.epoch_drain.waves.package
        for case in range(1, 15, 3):
            self.assertEqual(self.trace(case, 21)['processed'], [package('B').hex()])
            self.assertEqual(self.trace(case, 21)['expired'], [package('C').hex()])
            self.assertEqual(self.trace(case, 22)['expired'], [package('D').hex()])
            self.assertEqual(self.trace(case, 23)['expired'], [package('E').hex()])
            for slot in (22, 23, 24):
                state = self.states[case][slot]; parsed, _ = statistics_parse(state[chapter_key(13)], DEFAULT)
                self.assertEqual(parsed[3], []); self.assertEqual(state[chapter_key(16)], b'\0')
            self.assertEqual(metadata_parse(self.states[case][24][chapter_service(255, 99)], 105)[2][2], 21)

    def test_full_ring_skip_clears_only_after_actual_processing(self):
        """Twelve elapsed slots discard all unprocessed rows, but affordable B still processes before that projection."""
        package = reference.epoch_drain.waves.package
        for case in range(2, 15, 3):
            trace = self.trace(case, 23)
            self.assertEqual(trace['processed'], [package('B').hex()])
            self.assertEqual(trace['expired'], sorted(package(name).hex() for name in 'CDE'))
            state = self.states[case][24]
            self.assertEqual(state[chapter_key(14)], bytes(12))
            rows = reference.epoch_drain.waves.pipeline.accumulated(state[chapter_key(15)])
            self.assertEqual(rows[-3:], [package('A'), package('B'), b''])
            self.assertEqual(sum(len(row)//32 for row in rows), 2)
        self.assertEqual((self.evidence['transitions'], self.evidence['processed_reports']), (205, 45))
