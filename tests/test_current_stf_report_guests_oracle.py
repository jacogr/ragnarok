# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independence and cross-phase invariants for available-report guest complete maps."""
import unittest
import current_stf_report_guests_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_service_values_oracle import key as value_key
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class CurrentStfReportGuestsOracle(unittest.TestCase):
    """Classify effects using explicit guest semantics and normative report operands, never native output."""

    @classmethod
    def setUpClass(cls):
        """Calculate all expected blocks/maps once, before separate semantic invariants inspect them."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states = []
        for line in cls.lines:
            if line.startswith('P '): cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))])
            elif line.startswith('O '): cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])) )

    def state(self, case, slot):
        """Seven consecutive children begin with the authored complete slot1 original."""
        return self.states[case][slot-1]

    def activity(self, case, slot):
        """Read the independent C13 per-service rows indexed by their actual service identities."""
        parsed, _ = statistics_parse(self.state(case, slot)[chapter_key(13)], DEFAULT)
        return {row[0]: row for row in parsed[3]}

    def test_no_free_allowances_or_premature_execution(self):
        """Zero C12 allowances and four votes leave service maps unchanged until the actual per-core quorum."""
        for case, chain in enumerate(self.states):
            self.assertTrue(all(state[chapter_key(12)][-1:] == b'\0' for state in chain))
            for sid in (42, 99):
                original = chain[0][chapter_service(255, sid)]
                for slot in (2, 3, 4): self.assertEqual(self.state(case, slot)[chapter_service(255, sid)], original)
            self.assertEqual(self.state(case, 3)[chapter_key(10)], self.state(case, 4)[chapter_key(10)])
            self.assertEqual(self.activity(case, 4), {})

    def test_partial_availability_then_same_service_batch(self):
        """Quorum for core1 executes99 alone; two later reports produce two operands with one guest charge."""
        for case, mode in enumerate(reference.MODES):
            self.assertIsNotNone(reference.pending(self.state(case, 5)[chapter_key(10)])[0])
            self.assertIsNone(reference.pending(self.state(case, 5)[chapter_key(10)])[1])
            first, batch = self.activity(case, 5), self.activity(case, 7)
            self.assertEqual(set(first), {99}); self.assertEqual(set(batch), {99})
            self.assertEqual(first[99][9:], (1, 0, reference.guest_gas(mode)))
            self.assertEqual(batch[99][9:], (2, 0, reference.guest_gas(mode)))
            mixed = self.activity(case, 6)
            self.assertEqual(mixed[42][9:], (1, 0, 22))
            self.assertEqual(mixed[99][3:9], (2, 27, 5, 7, 9, 11))
            self.assertEqual(mixed[99][9:], (0, 0, 0))

    def test_literal_storage_rollback_checkpoint_and_timestamps(self):
        """Exceptional Y selection retains only checkpointed effects; every actual invocation updates its timestamp."""
        storage = value_key('S', 99, b'\7')
        for case, mode in enumerate(reference.MODES):
            for slot in (5, 7):
                state = self.state(case, slot)
                if mode == 'delete' or mode == 'panic-rollback': self.assertNotIn(storage, state)
                else: self.assertEqual(state[storage], bytes([9, 8, 7]))
                self.assertEqual(metadata_parse(state[chapter_service(255, 99)], 105)[2][2], slot)
            self.assertEqual(metadata_parse(self.state(case, 8)[chapter_service(255, 42)], 105)[2][2], 6)
            self.assertEqual(metadata_parse(self.state(case, 8)[chapter_service(255, 99)], 105)[2][2], 7)

    def test_processed_package_history_ages_and_immediate_ready_stays_empty(self):
        """Four processed packages remain in distinct correctly shifted C15 rows, including the two-report batch."""
        packages = [reference.digest(f'immediate package slot{s} core{c}'.encode()) for s, c in ((3, 0), (3, 1), (6, 0), (6, 1))]
        for case, chain in enumerate(self.states):
            self.assertTrue(all(state[chapter_key(14)] == bytes(12) for state in chain))
            rows = reference.accumulated(self.state(case, 8)[chapter_key(15)])
            self.assertEqual(rows[:8], [b'']*8)
            self.assertEqual(rows[8:], [packages[1], packages[0], b''.join(sorted(packages[2:])), b''])

    def test_outputs_and_later_empty_block(self):
        """Only retained service99 yields enter C16; empty blocks preserve service state and age history without execution."""
        for case, mode in enumerate(reference.MODES):
            for slot in range(2, 9):
                state = self.state(case, slot)
                expected = b'\1'+(99).to_bytes(4, 'little')+reference.COMMITMENT if slot in (5, 7) and mode != 'panic-rollback' else b'\0'
                self.assertEqual(state[chapter_key(16)], expected)
            self.assertEqual(self.activity(case, 8), {})
            before, after = self.state(case, 7), self.state(case, 8)
            for sid in (42, 99): self.assertEqual(before[chapter_service(255, sid)], after[chapter_service(255, sid)])
        self.assertEqual((self.evidence['transitions'], self.evidence['guest_executions'], self.evidence['processed_reports']), (35, 15, 20))
