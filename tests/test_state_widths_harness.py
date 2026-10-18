# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal fixed/natural alternatives protect the diagnostic investigation without upstream execution.

Exposes StateWidthsHarness for unittest discovery; test methods exercise the stated contracts.
"""
import unittest
from state_widths_oracle import privilege_wire, statistics_wire, statistics_candidate


# Hand-authored values distinguish representations through actual bytes rather than decimal type names.
class StateWidthsHarness(unittest.TestCase):
    # Nonzero service/gas values disambiguate all four privilege candidates at the same known offset.
    def test_privilege_alternatives(self):
        source = dict(bless=0, assign=[0, 0], designate=0, register=0,
            always_acc=[dict(id=1729, gas=100000)])
        values = [privilege_wire(source, k, g) for k in (0, 4) for g in (0, 8)]
        self.assertEqual(len(set(values)), 4)
        self.assertEqual(values[-1], bytes(20)+b'\1\xc1\6\0\0\xa0\x86\1'+bytes(5))
        self.assertEqual([len(v) for v in values], [26, 31, 28, 33])

    # Empty dictionaries contain no key/gas pair bytes and therefore cannot settle their widths.
    def test_empty_dictionary(self):
        source = dict(bless=0, assign=[0, 0], designate=0, register=0, always_acc=[])
        self.assertEqual({privilege_wire(source, k, g) for k in (0, 4) for g in (0, 8)}, {bytes(21)})

    # A wide E4 ID and positive variable-width gas distinguish key and gas alternatives independently.
    def test_statistics_nonzero(self):
        source = ([bytes(144), bytes(144)], [[0]*7+[100000], [0]*8],
            [(3953987649, [0, 0, 0, 161372, 0, 0, 0, 0, 0, 0, 445424])])
        raw = statistics_wire(source, 4, 0)
        selected = statistics_candidate(raw, 4, 0)
        self.assertTrue(selected['matches'])
        self.assertEqual(selected['services'], [3953987649])
        self.assertEqual(selected['core_gas'], [100000, 0])
        self.assertEqual(selected['service_gas'], [(161372, 445424)])
        for key_width, gas_width in ((0, 0), (0, 8), (4, 8)):
            self.assertFalse(statistics_candidate(raw, key_width, gas_width)['matches'])

    # No source fields survive a late truncation or suffix failure in a diagnostic candidate.
    def test_statistics_extent(self):
        source = ([bytes(144), bytes(144)], [[0]*8, [0]*8], [(7, [0]*11)])
        raw = statistics_wire(source, 4, 0)
        for data in (raw[:-1], raw+b'\0'):
            verdict = statistics_candidate(data, 4, 0)
            self.assertFalse(verdict['matches'])
            self.assertEqual(set(verdict), {'matches', 'error'})

    # Alternative schemas must not sort or deduplicate a hostile dictionary to make its bytes match.
    def test_statistics_order(self):
        source = ([bytes(144), bytes(144)], [[0]*8, [0]*8], [(8, [0]*11), (7, [0]*11)])
        verdict = statistics_candidate(statistics_wire(source, 4, 0), 4, 0)
        self.assertEqual(verdict, dict(matches=False, error='noncanonical_order'))

    # Empty services leave the key alternatives indistinguishable; zero variable gas still has one-byte framing.
    def test_statistics_empty(self):
        source = ([bytes(144), bytes(144)], [[0]*8, [0]*8], [])
        raw = statistics_wire(source, 4, 0)
        self.assertTrue(statistics_candidate(raw, 0, 0)['matches'])
        self.assertTrue(statistics_candidate(raw, 4, 0)['matches'])
        self.assertFalse(statistics_candidate(raw, 4, 8)['matches'])


# Literal tests have no compiler, network, native-library or upstream execution dependency.
if __name__ == '__main__':
    unittest.main()
