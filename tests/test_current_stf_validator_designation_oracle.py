# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent designation terminal selection, delayed activation and complete two-epoch continuity."""
import unittest
import current_stf_validator_designation_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account


class ValidatorDesignationOracle(unittest.TestCase):
    """Changing staging does not prematurely change active validators, ring roots or pending membership."""

    def test_staging_pending_active_order(self):
        """Selected records stage at4, become pending12 and active24; rejected/discarded writes preserve the original membership."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Ten independently signed successors include both genuine epoch boundaries.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        raw,root=reference.staging();roster=reference.epoch.roster(b'\6'+raw)
        for profile,states in zip(reference.PROFILES,chains):
            retained=profile in ('designate','checkpoint-panic')
            original=states[0];selected=roster if retained else reference.epoch.roster(original[chapter_key(7)])
            old_pending=reference.epoch.consensus(original[chapter_key(4)])[0]
            self.assertEqual(reference.epoch.roster(states[3][chapter_key(7)]),selected)
            self.assertEqual(reference.epoch.consensus(states[3][chapter_key(4)])[0],old_pending)
            self.assertEqual(reference.epoch.roster(states[6][chapter_key(8)]),old_pending)
            self.assertEqual(reference.epoch.consensus(states[6][chapter_key(4)])[0],selected)
            self.assertEqual(reference.epoch.roster(states[9][chapter_key(8)]),selected)
            self.assertEqual(reference.epoch.roster(states[9][chapter_key(9)]),old_pending)
            expected=root if retained else reference.epoch.consensus(original[chapter_key(4)])[1]
            self.assertEqual(reference.epoch.consensus(states[6][chapter_key(4)])[1],expected)
            self.assertEqual(reference.epoch.consensus(states[9][chapter_key(4)])[1],expected)
            self.assertEqual(account(states[10][chapter_service(255,99)],105)[2][2],4)
        self.assertEqual((evidence['transitions'],evidence['chains']),(50,5))
