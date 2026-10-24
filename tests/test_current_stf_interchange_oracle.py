# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent exact identity coverage and complete current-profile STF interchange witnesses."""
import unittest
import current_stf_interchange_oracle as reference
from current_stf_oracle import decode_checkpoint
from state_service_values_oracle import key as value_key
from state_layout_oracle import digest


class InterchangeOracle(unittest.TestCase):
    """Independent identity ASCII never guesses a raw key from a complete physical map."""

    def test_full_maps_and_detached_identities(self):
        """Every successor includes exact raw identities, including empty keys and genuinely pending requests."""
        commands,lines,evidence=reference.expected_observations()
        self.assertEqual((evidence['transitions'],evidence['chains']),(255,40))
        self.assertEqual(sum(line.startswith('L ') for line in lines),255)
        self.assertTrue(all(line.endswith(' exchange') for line in commands if line.startswith('C ')))
        for index,line in enumerate(lines):
            if line.startswith('L '):
                text=bytes.fromhex(line[2:]).decode()
                self.assertTrue(text.startswith('ragnarok-current-logical-source-v1\ns=42\n'))
                self.assertEqual(text.count('k=\n'),2)
                self.assertIn('p='+digest(b'').hex()+'\n',text)
                self.assertTrue(lines[index+1].startswith('O ')) # Identity text is bound to this exact independently calculated successor.

    def test_unenumerated_identity_is_refused(self):
        """A complete map containing another physical identity cannot be silently exported as the authored declaration subset."""
        import current_stf_bless_allowances_oracle as source
        original=source.original('publish');altered=dict(original)
        altered[value_key('S',42,b'unknown')]=b'x'
        with self.assertRaises(AssertionError):
            reference.declarations(altered,original,None)
