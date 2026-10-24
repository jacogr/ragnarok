# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent queued old-report identity, current service-code lookup and incarnation authority invariants."""
import hashlib
import unittest
import current_stf_queued_incarnation_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account
from state_service_values_oracle import key as value_key


class QueuedIncarnationOracle(unittest.TestCase):
    """Already-signed old report bytes survive C10 unchanged, while accumulation resolves code from the selected current account."""

    def test_old_report_current_code_and_later_authority(self):
        """Recreation cannot rewrite a queued code identity or bypass prior-bound supervision, yet its real code executes when released."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Every old77 is genuinely empty before the signed old report is admitted.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states,trace in zip(reference.PROFILES,chains,evidence['traces']):
            pending=reference.transfers.pipeline.pending(states[3][chapter_key(10)]);old=pending[1]['guarantee']['report']
            self.assertEqual(hashlib.sha256(old).hexdigest(),trace['old_report_sha256'])
            self.assertEqual(pending[1]['registered'],3)
            code=account(states[3][chapter_service(255,77)],105)[0];self.assertEqual(code==bytes(32),profile=='creator-panic')
            events=trace['events'];self.assertTrue(events[1]['old_report_released'])
            self.assertEqual(events[1]['gas'][77]==0,profile=='creator-panic')
            storage=value_key('S',42,b'\7');self.assertNotIn(storage,states[4])
            success=profile in ('rebind','checkpoint-panic');self.assertEqual(storage in states[6],success)
            self.assertEqual(account(states[6][chapter_service(255,42)],105)[2][2],5)
            self.assertEqual(account(states[6][chapter_service(255,77)],105)[2][2],7)
        self.assertEqual((evidence['transitions'],evidence['chains']),(35,5))
