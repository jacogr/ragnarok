# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject incomplete, reordered and corrupt pricing samples before reporting performance."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_pricing_benchmark import parse_output


def samples():
    """Author complete rows independently of the native benchmark and parser."""
    return [f'PVM_PRICING_LOOKUP,{mode},{sample},{100+sample},3000000'
            for mode in range(2) for sample in range(13)]


class PricingBenchmarkTests(unittest.TestCase):
    """A complete positive control accompanies every report-integrity rejection family."""

    def test_complete_cold_and_warm_rows(self):
        """Retain cold row zero and all thirteen samples from each distinct policy."""
        rows = parse_output('\n'.join(samples()))
        self.assertEqual(len(rows), 26)
        self.assertEqual(rows[0]['sample'], 0)
        self.assertEqual(rows[13]['mode'], 1)

    def test_corruptions(self):
        """Missing/extra/reordered rows and bad fields cannot yield a partial success report."""
        valid = samples()
        corruptions = [valid[:-1], valid+[valid[-1]], valid[1:]+valid[:1],
                       ['noise']+valid[1:], ['PVM_PRICING_LOOKUP,0,0,0,3000000']+valid[1:],
                       ['PVM_PRICING_LOOKUP,0,0,100,2999999']+valid[1:],
                       ['PVM_PRICING_LOOKUP,0,0,no,3000000']+valid[1:]]
        for rows in corruptions:
            # Each mutation preserves the other rows so its own broken protocol obligation is exercised.
            with self.subTest(first=rows[0], count=len(rows)):
                with self.assertRaises(ValueError):
                    parse_output('\n'.join(rows))
