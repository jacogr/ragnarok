# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent creation, funding, request-only code, retirement and logical completeness invariants across rotation."""
import unittest
from scenario_states import case_states
import current_stf_rotation_creation_oracle as reference
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account_parse
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from reporting_declarations_oracle import declaration, encode


class RotationCreationTests(unittest.TestCase):
    """Check protocol relationships before any native observation, including refused logical inventories."""

    @classmethod
    def setUpClass(cls):
        """Derive every complete mathematical case once and preserve original maps for later invariants."""
        cls.cases = {case['name']: case for case in reference.cases()}
        cls.states = case_states(cls.cases.values())

    def test_public_ids_and_request_only_code(self):
        """Actual execution slots seed independent public cursors; creation requests code without supplying a preimage."""
        for profile,count in (('halt',4),('checkpoint-panic',4),('two-children',8),('panic',0),('reserved-length',0)):
            case = self.cases['basic-'+profile];ids = [sid for _,group in case['births'] for sid in group]
            self.assertEqual(len(ids),count);self.assertEqual(len(set(ids)),count)
            state = self.states['basic-'+profile][25]
            for sid in ids:
                self.assertTrue(65536<=sid<2**32-256)
                code,wide,narrow = account_parse(state[chapter_service(255,sid)],105)
                self.assertEqual((wide[0],wide[1],wide[4]),(0,0,81+len(reference.creation.replacement())))
                self.assertIn(narrow[1],(12,13,24,25));self.assertEqual(narrow[3:],(99,99,0))
                self.assertEqual(state[request_key(sid,code,len(reference.creation.replacement()))],request_wire(()))
                self.assertNotIn(value_key('P',sid,code),state)

    def test_reserved_funding_is_selected_exactly_once(self):
        """A later FULL cannot repeat the first224-token selected-pool debit or overwrite its child."""
        for index,profile in enumerate(reference.reserved.PROFILES[:4]):
            states = self.states['reserved-'+profile]
            before = account_parse(states[1][chapter_service(255,99)],105)[1]
            after = account_parse(states[25][chapter_service(255,99)],105)[1]
            source = int(index in (1,3));expected = list(before[:2]);expected[source]-=224
            self.assertEqual(after[:2],tuple(expected))
            child = account_parse(states[25][chapter_service(255,77)],105)
            self.assertEqual(child[1][:2],(224,0) if index in (0,1) else (0,224))
            self.assertEqual(child[2][1],12)
            self.assertTrue(all(states[slot][chapter_service(255,77)]==states[12][chapter_service(255,77)] for slot in (13,24,25)))

    def test_retirement_refunds_both_pools_once(self):
        """Selected ejection refunds7+11 to caller liquid once, while panic/unauthorized/missing targets keep the donor."""
        for profile in reference.ejection.PROFILES:
            states = self.states['ejection-'+profile];selected = profile in ('eject','checkpoint-panic')
            initial = account_parse(states[1][chapter_service(255,99)],105)[1][0]
            self.assertEqual(account_parse(states[25][chapter_service(255,99)],105)[1][0],initial+18*int(selected))
            self.assertEqual(chapter_service(255,77) in states[25],not selected)
            self.assertIn(chapter_service(255,77),states[1])

    def test_logical_completeness_is_not_optional(self):
        """Known forward GP identities cover every authored key; unknown storage is refused before native execution."""
        case = self.cases['basic-halt'];ids = [row[0] for row in case['inventory_rows']]
        self.assertEqual(declaration(case,ids,blobs=(reference.creation.replacement(),))[0],case['inventory'])
        changed = dict(case);changed['initial'] = dict(case['initial'])
        changed['initial'][value_key('S',99,b'\x19')] = b'not-declared'
        with self.assertRaisesRegex(AssertionError,'logical namespace'):
            declaration(changed,ids,blobs=(reference.creation.replacement(),))
        controls = reference.negative_inventory_cases()
        self.assertEqual([row['name'] for row in controls],['missing-child','missing-code-request','truncated-declaration','too-many-services'])
        self.assertTrue(all(len(row['requests'][0].split())==6 for row in controls))

    def test_transport_limits_and_duplicates(self):
        """Identity-only transport rejects duplicate IDs, reserved lengths and excess services before encoding."""
        for rows in ([(42,[],[]),(42,[],[])],[(i,[],[]) for i in range(17)],[(42,[],[(bytes(32),[2**32-2])])]):
            with self.assertRaises(AssertionError):
                encode(rows)


if __name__ == '__main__':
    unittest.main()
