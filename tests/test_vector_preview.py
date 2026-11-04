# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bind the new preview scenarios to their published effects in both populations.

These are source-data checks; maintained native kernel and dispute replays provide execution evidence.
"""
import hashlib
import unittest
from state_accounts_oracle import blob


class PreviewEffects(unittest.TestCase):
    """Preserve the specific discard/provision/privilege and marker-sequence witnesses being adopted."""

    def test_discarded_creation(self):
        """Discarded creation retains the original account domain and registrar endowment balance."""
        for profile in ('tiny', 'full'):
            case = blob(f'stf/accumulate/{profile}/discarded_junior_creates_no_service-1.json')
            before = {row['id']: row['data'] for row in case['pre_state']['accounts']}
            after = {row['id']: row['data'] for row in case['post_state']['accounts']}
            self.assertEqual(set(before), {0, 1, 1729})
            self.assertEqual(set(after), set(before))
            self.assertEqual(after[1]['service']['balance'], before[1]['service']['balance'])

    def test_discarded_provider(self):
        """A junior's retained provision adds the actual requested preimage to its recipient."""
        for profile in ('tiny', 'full'):
            case = blob(f'stf/accumulate/{profile}/discarded_junior_keeps_provisions-1.json')
            before = {row['id']: row['data'] for row in case['pre_state']['accounts']}
            after = {row['id']: row['data'] for row in case['post_state']['accounts']}
            prior = {row['hash'] for row in before[1729]['preimage_blobs']}
            added = [row for row in after[1729]['preimage_blobs'] if row['hash'] not in prior]
            self.assertEqual(len(added), 1)
            self.assertEqual(added[0]['hash'], '0x'+hashlib.blake2b(
                bytes.fromhex(added[0]['blob'][2:]), digest_size=32).hexdigest())
            self.assertEqual(after[1]['service']['balance'], before[1]['service']['balance'])

    def test_discarded_manager(self):
        """The original manager remains while the independently selected designator handover survives."""
        for profile in ('tiny', 'full'):
            case = blob(f'stf/accumulate/{profile}/discarded_manager_privileges_revert-1.json')
            before = case['pre_state']['privileges']
            after = case['post_state']['privileges']
            self.assertEqual(before['bless'], 1)
            self.assertEqual(after['bless'], 1)
            self.assertEqual(before['designate'], 2)
            self.assertEqual(after['designate'], 4)
            for role in ('assign', 'register', 'always_acc'):
                # Other original authority and allowance fields must not acquire discarded manager changes.
                self.assertEqual(after[role], before[role])

    def test_repeated_offender_markers(self):
        """Culprit/fault overlap contributes both entries to the ordered output marker sequence."""
        for profile in ('tiny', 'full'):
            case = blob(f'stf/disputes/{profile}/progress_with_faults-8.json')
            evidence = case['input']['disputes']
            shared = {row['key'] for row in evidence['culprits']} & {
                row['key'] for row in evidence['faults']}
            self.assertEqual(len(shared), 1)
            key = next(iter(shared))
            self.assertEqual(case['output']['ok']['offenders_mark'], [key, key])
