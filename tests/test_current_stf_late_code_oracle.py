# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Whole-map invariants for requested code arriving after accumulation in the same block."""
import unittest
import current_stf_late_code_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service, digest
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class CurrentStfLateCodeOracle(unittest.TestCase):
    """Code absence, fulfillment and later execution are independently predicted at complete-map boundaries."""

    @classmethod
    def setUpClass(cls):
        """Calculate all original and successor maps once before inspecting semantic consequences."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations(); cls.states = []
        for line in cls.lines:
            if line.startswith('P '): cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))])
            elif line.startswith('O '): cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))

    def state(self, case, slot):
        """Nine consecutive children follow each complete slot1 original."""
        return self.states[case][slot-1]

    def activity(self, case, slot):
        """Return C13 service activity by explicit service identity."""
        parsed, _ = statistics_parse(self.state(case, slot)[chapter_key(13)], DEFAULT)
        return {row[0]: row for row in parsed[3]}

    def test_same_block_fulfillment_cannot_retroactively_execute(self):
        """Reports at5 always skip; at7 only code provided at5 can execute."""
        for case, (mode, supplied) in enumerate(reference.CASES):
            self.assertEqual(self.activity(case, 5)[99][9:], (1, 0, 0))
            expected = reference.pipeline.guest_gas(mode) if supplied == 5 else 0
            self.assertEqual(self.activity(case, 7)[99][9:], (2, 0, expected))
            self.assertEqual(self.activity(case, 9)[99][9:], (2, 0, reference.pipeline.guest_gas(mode)))
            self.assertEqual(self.state(case, supplied)[chapter_key(16)], b'\0')
            self.assertEqual(metadata_parse(self.state(case, 5)[chapter_service(255, 99)], 105)[2][2], 5)

    def test_exact_requested_code_and_reserved_footprint(self):
        """Only requested exact code bytes enter P; fulfillment records its actual slot without changing reservations."""
        for case, (mode, supplied) in enumerate(reference.CASES):
            raw = reference.code(mode); code_key = value_key('P', 99, digest(raw)); request = request_key(99, digest(raw), len(raw))
            for slot in range(1, 11):
                state = self.state(case, slot)
                if slot < supplied:
                    self.assertNotIn(code_key, state); self.assertEqual(state[request], b'\0')
                else:
                    self.assertEqual(state[code_key], raw); self.assertEqual(state[request], request_wire((supplied,)))
            self.assertEqual(self.activity(case, supplied)[99][1:3], (1, len(raw)))
            self.assertEqual(metadata_parse(self.state(case, supplied)[chapter_service(255, 99)], 105)[1][4], metadata_parse(self.states[case][0][chapter_service(255, 99)], 105)[1][4])

    def test_skipped_reports_are_processed_without_automatic_replay(self):
        """Code-unavailable reports still enter C15; only subsequently reported operands run later."""
        for case in range(10):
            self.assertEqual(self.state(case, 10)[chapter_key(14)], bytes(12))
            rows = reference.pipeline.accumulated(self.state(case, 10)[chapter_key(15)])
            self.assertEqual(sum(len(row)//32 for row in rows), 6)
            self.assertEqual(self.activity(case, 10), {})
        self.assertEqual(self.evidence['transitions'], 90)
