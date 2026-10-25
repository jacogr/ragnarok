# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard inline source-file transitions and exclusive/call cost accounting in deep profiles."""
import unittest
from pvm_execution_attribution import attribution


def profile():
    """Two source files and an inclusive call contain exactly thirty exclusive instructions."""
    return ('# callgrind format\npositions: instr line\nevents: Ir Dr\nsummary: 30 0\n'
            'fl=outer.c\nfn=outer\n0x10 10 4\nfi=inline.c\n0x11 20 6\n'
            'cfn=helper\ncalls=2 0x20 30\n0x12 21 20\nfe=outer.c\n'
            'fn=helper\n0x20 30 20\ntotals: 30 0\n')


class AttributionTests(unittest.TestCase):
    """Independent fixtures prevent double counting, invented line attribution and retained call tails."""

    def test_inline_file_changes_and_call_costs(self):
        """The inline source changes cost ownership while a helper's inclusive edge is counted separately."""
        result = attribution(profile())
        self.assertEqual(dict(result['functions']), {'outer': 10, 'helper': 20})
        self.assertEqual(sum(row['ir'] for row in result['lines']), 30)
        self.assertEqual(result['calls'][0]['calls'], 2)
        self.assertEqual(result['calls'][0]['inclusive_ir'], 20)
        self.assertIn(dict(file='inline.c', line=20, function='outer', ir=6), result['lines'])

    def test_refuse_partial_or_ambiguous_positions(self):
        """Missing counters, unsupported compression and lost function/file context refuse publication."""
        for text in (profile().replace('totals: 30', 'totals: 31'),
                     profile().replace('0x11 20', '+1 20'),
                     profile().replace('fl=outer.c\n', ''),
                     profile().replace('cfn=helper\n', ''),
                     profile()+'calls=1 0x30 31\n'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                attribution(text)


if __name__ == '__main__':
    unittest.main() # Importing the parser never starts native profiling.
