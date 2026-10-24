# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent nonempty allowance selection, canonicalization and next-block participation invariants."""
import unittest
import current_stf_bless_allowances_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key,chapter_service
from state_accounts_oracle import parse as account
from state_statistics_oracle import parse as statistics,DEFAULT
from state_privileges_oracle import wire as privileges_wire


class BlessAllowancesOracle(unittest.TestCase):
    """New allowances cannot schedule their members retroactively, and empty operands do not invent report counts."""

    def test_canonical_dictionary_and_later_execution(self):
        """Exact-pair deduplication preserves raw-item gas; retained nonempty state starts genuine later free invocations."""
        _,lines,evidence=reference.expected_observations();chains=[]
        for line in lines:
            if line.startswith('P '):
                chains.append([]) # Every independently authored original has an empty allowance set.
            if line.startswith(('P ','O ')):
                chains[-1].append(decode_checkpoint(bytes.fromhex(line[2:])))
        for profile,states in zip(reference.PROFILES,chains):
            retained=profile not in ('panic','unauthorized');at4=states[3];at5=states[4]
            self.assertEqual(account(at4[chapter_service(255,42)],105)[2][2],0)
            self.assertEqual(account(at5[chapter_service(255,42)],105)[2][2],5 if retained else 0)
            if retained:
                self.assertEqual(at4[chapter_key(12)],privileges_wire((99,0,0,[0,0],sorted(set(reference.pairs(profile))))))
                rows=statistics(at5[chapter_key(13)],DEFAULT)[0][3];target=next(row for row in rows if row[0]==42)
                self.assertEqual(target[9:12],(0,0,22))
                source=next(row for row in rows if row[0]==99) # Admission at5 keeps a row even without a free invocation.
                event=evidence['traces'][reference.PROFILES.index(profile)][3]
                self.assertEqual(source[9:12],(0,0,event['gas99']))
            else:
                self.assertEqual(at4[chapter_key(12)],states[0][chapter_key(12)])
        normal=evidence['traces'][0][2]['gas99'];duplicates=evidence['traces'][3][2]['gas99']
        self.assertEqual(duplicates-normal,20)
        self.assertEqual((evidence['transitions'],evidence['chains']),(36,6))
