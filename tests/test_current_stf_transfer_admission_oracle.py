# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-map admission, outgoing gas and incoming prepaid-block boundary invariants."""
import unittest
import current_stf_transfer_admission_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics, DEFAULT


class TransferAdmissionOracle(unittest.TestCase):
    """Whole-map effects remain atomic across endpoint, pool, funding, memory and gas refusals."""

    def test_boundary_effects_and_no_aliasing(self):
        """Exact host budget retains its debit; one above exhausts gas without producing an outgoing record."""
        _, lines, evidence = reference.expected_observations()
        states = []
        for line in lines:
            if line.startswith('P '):
                states.append([]) # Retain each explicit original with its complete four-step state chain.
            if line.startswith(('P ', 'O ')):
                states[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for index, profile in enumerate(reference.PROFILES):
            state, after = states[index][3], states[index][4]
            trace = evidence['traces'][index][0]
            rows = {row[0]: row for row in statistics(state[chapter_key(13)], DEFAULT)[0][3]}
            keep = profile in ('minimum-zero-execution', 'exact-outgoing-budget', 'recipient-one-short', 'recipient-exact')
            self.assertEqual(trace['retained'], keep)
            self.assertEqual(rows[99][9:11], (1, 0))
            self.assertEqual(sorted(rows), [42, 99] if keep else [99])
            self.assertEqual(account(state[chapter_service(255, 99)], 105)[1][0], 999993 if keep else 1000000)
            self.assertEqual(account(state[chapter_service(255, 42)], 105)[1][0], 7 if keep else 0)
            self.assertEqual(account(state[chapter_service(255, 42)], 105)[2][2], 4 if keep else 0)
            if keep:
                self.assertEqual(rows[42][9:], (0, 1, 22 if profile in ('exact-outgoing-budget', 'recipient-exact') else 0))
            for sid in (42, 99):
                self.assertEqual(state[chapter_service(255, sid)], after[chapter_service(255, sid)])
            expected_gas = 100000 if profile in ('exact-outgoing-budget', 'outgoing-one-above') else 678+({'minimum-zero-execution': 10, 'recipient-one-short': 21, 'recipient-exact': 22}.get(profile, 0))
            self.assertEqual(rows[99][11], expected_gas)
        self.assertEqual((evidence['transitions'], evidence['chains']), (56, 14))
