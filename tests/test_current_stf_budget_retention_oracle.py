# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Complete-map invariants for positive residual gas, actual processed prefixes and later drain."""
import unittest
import current_stf_budget_retention_oracle as reference
from current_stf_reporting_oracle import ready
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as metadata_parse
from state_statistics_oracle import parse as statistics_parse, DEFAULT


class CurrentStfBudgetRetentionOracle(unittest.TestCase):
    """Cross-check all three declared-gas profiles independently of native queue observations."""

    @classmethod
    def setUpClass(cls):
        """Calculate all expected maps once and retain them in chain/slot order."""
        cls.requests, cls.lines, cls.evidence = reference.expected_observations()
        cls.states = []
        for line in cls.lines:
            if line.startswith('P '): cls.states.append([decode_checkpoint(bytes.fromhex(line[2:]))])
            elif line.startswith('O '): cls.states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))

    def state(self, case, slot):
        """Each authored original is slot1 and advances through slot11."""
        return self.states[case][slot-1]

    def test_serial_retention_edits_only_actual_processed_dependencies(self):
        """Q may expose five candidates, but only A is processed; posterior dependencies use the actual prefix."""
        key = reference.waves.package
        for case in range(0, 15, 3):
            state = self.state(case, 7); rows = ready(state[chapter_key(14)])
            expected = {4: ('B', []), 5: ('C', ['B']), 6: ('D', ['C']), 7: ('E', ['B', 'D'])}
            for at, (name, dependencies) in expected.items():
                self.assertEqual([(wire[:32], deps) for wire, deps in rows[at]], [(key(name), b''.join(sorted(key(d) for d in dependencies)))])
            trace = self.evidence['plans'][case][5]
            self.assertEqual(trace['prefixes'], [[key('A').hex()]])
            self.assertEqual(trace['remaining_gas'], 299978)
            self.assertEqual(reference.waves.pipeline.accumulated(state[chapter_key(15)])[-1], key('A'))

    def test_exact_residual_boundary_and_one_gas_refusal(self):
        """B299978 runs after A22; B299979 remains queued with an empty dependency set until the next block."""
        for start in range(0, 15, 3):
            fit, above = start+1, start+2
            self.assertEqual(self.evidence['plans'][fit][5]['prefixes'], [[reference.waves.package('A').hex()], [reference.waves.package('B').hex()]])
            self.assertEqual(self.evidence['plans'][above][5]['prefixes'], [[reference.waves.package('A').hex()]])
            self.assertEqual(len(ready(self.state(fit, 7)[chapter_key(14)])[4]), 0)
            self.assertEqual(ready(self.state(above, 7)[chapter_key(14)])[4][0][1], b'')

    def test_all_retained_reports_drain_in_later_empty_blocks(self):
        """Every package enters processed history once; dependency-free retention remains eligible without new availability."""
        for case, (mode, profile) in enumerate(reference.CASES):
            traces = self.evidence['plans'][case]
            processed = [key for trace in traces for prefix in trace['prefixes'] for key in prefix]
            self.assertEqual(processed, [reference.waves.package(name).hex() for name in 'ABCDE'])
            self.assertEqual(self.state(case, 11)[chapter_key(14)], bytes(12))
            end = 10 if profile == 'exact-residual-fit' else 11
            self.assertEqual(metadata_parse(self.state(case, 11)[chapter_service(255, 99)], 105)[2][2], end)
            for slot in range(8, end+1):
                parsed, _ = statistics_parse(self.state(case, slot)[chapter_key(13)], DEFAULT)
                self.assertEqual(parsed[3][0][9:], (1, 0, reference.waves.pipeline.guest_gas(mode)))
        self.assertEqual((self.evidence['transitions'], self.evidence['processed_reports'], self.evidence['guest_executions']), (150, 75, 75))
