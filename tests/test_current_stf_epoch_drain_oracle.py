# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Whole-map invariants binding deferred guest execution to real epoch markers and statistics rotation."""
import unittest
import current_stf_epoch_drain_oracle as reference
from current_stf_oracle import decode_checkpoint
from current_stf_reporting_oracle import ready
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class CurrentStfEpochDrainOracle(unittest.TestCase):
    """Check the independent global/guest composition across a genuine epoch transition."""

    @classmethod
    def setUpClass(cls):
        """Retain complete maps and full signed blocks before any native execution."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations(); cls.states = []; cls.blocks = []
        for line in cls.lines:
            if line.startswith('P '): cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))]); cls.blocks.append([])
            elif line.startswith('B '): cls.blocks[-1].append(bytes.fromhex(line[2:]))
            elif line.startswith('O '): cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))

    def state(self, case, slot):
        """Consecutive children advance the explicit original from1 through16."""
        return self.states[case][slot-1]

    def test_epoch_marker_and_validator_statistics_rotation(self):
        """Block12 carries the actual epoch marker and rotates the whole previous accumulator exactly once."""
        for case in range(5):
            self.assertEqual(self.blocks[case][10][100], 1)
            self.assertEqual(self.blocks[case][11][100], 0)
            before, _ = statistics_parse(self.state(case, 11)[chapter_key(13)], DEFAULT)
            after, _ = statistics_parse(self.state(case, 12)[chapter_key(13)], DEFAULT)
            self.assertEqual(after[1], before[0]); self.assertEqual(after[0][0][0], 1)
            self.assertEqual(self.state(case, 12)[chapter_key(6)][32:64], self.state(case, 11)[chapter_key(6)][:32])

    def test_waiters_survive_crossing_and_drain_with_real_guest_effects(self):
        """A processes at11; B,C,D,E each execute in the new epoch under a fresh block budget."""
        for case, mode in enumerate(reference.waves.pipeline.MODES):
            self.assertEqual(sum(map(len, ready(self.state(case, 11)[chapter_key(14)]))), 4)
            self.assertEqual(metadata_parse(self.state(case, 11)[chapter_service(255, 99)], 105)[2][2], 0)
            for slot in range(12, 16):
                state = self.state(case, slot); parsed, _ = statistics_parse(state[chapter_key(13)], DEFAULT)
                self.assertEqual(parsed[3][0][9:], (1, 0, reference.waves.pipeline.guest_gas(mode)))
                self.assertEqual(metadata_parse(state[chapter_service(255, 99)], 105)[2][2], slot)
                self.assertEqual(sum(map(len, ready(state[chapter_key(14)]))), 15-slot)
            self.assertEqual(self.state(case, 16)[chapter_key(14)], bytes(12))
            self.assertEqual(self.state(case, 16)[chapter_key(16)], b'\0')

    def test_history_preserves_pre_and_post_epoch_packages(self):
        """Processed history shifts once per block and retains all five exact identities through the final empty child."""
        for case in range(5):
            rows = reference.waves.pipeline.accumulated(self.state(case, 16)[chapter_key(15)])
            self.assertEqual(rows[-6:], [reference.waves.package(name) for name in 'ABCDE']+[b''])
        self.assertEqual((self.evidence['transitions'], self.evidence['processed_reports']), (75, 25))
