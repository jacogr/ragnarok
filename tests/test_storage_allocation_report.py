# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independently authored allocator events preserve native trajectory and unavailable-operation checks."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from storage_allocation_report import parse_allocations, allocation_phases
from test_storage_growth_report import output


def observation(engine='managed'):
    """Keep one fully witnessed native sample behind a separately authored ordered checkpoint prefix."""
    native = output(engine, 8192, 64).split('publication\t8192\t64\tsweep\t1\t')[0]
    prefix = ''.join(f'allocation\t{phase}\t{(index+1)*100}\n'
                     for index, phase in enumerate(allocation_phases(engine)))
    return prefix+native


class StorageAllocationReportTests(unittest.TestCase):
    """Incomplete and substituted counters cannot become a successful allocator panel."""

    def test_all_three_backend_plans(self):
        """Actual unavailable phases remain absent, with exact counts for every supported backend."""
        for engine, count in (('memory', 10), ('journal', 9), ('managed', 11)):
            with self.subTest(engine=engine):
                rows = parse_allocations(observation(engine), engine, 8192, 64)['allocations']
                self.assertEqual(len(rows), count)
                self.assertEqual(rows[-1]['phase'], 'closed')

    def test_malformed_missing_reordered_and_late_events(self):
        """Counter syntax, bounds, order and final native coverage are independently required."""
        good = observation()
        cases = [good.replace('allocation\tfixture\t100\n', ''),
                 good.replace('fixture\t100', 'owner\t100'),
                 good.replace('fixture\t100', 'fixture\t-1'),
                 good.replace('fixture\t100', 'fixture\tTrue'),
                 good.replace('fixture\t100', 'fixture\t01'),
                 good.replace('fixture\t100', 'fixture\t'+str(1<<63)),
                 good+'allocation\tclosed\t10\n', good.split('publication\t')[0],
                 good.replace('allocation\tfixture\t100\n', 'allocation\tfixture\t100\n'*2)]
        for value in cases:
            with self.subTest(value=cases.index(value)), self.assertRaises(ValueError):
                parse_allocations(value, 'managed', 8192, 64)

    def test_case_substitution_refuses(self):
        """A valid checkpoint prefix cannot authorize another backend or fixture extent."""
        for engine, count in (('memory', 8192), ('managed', 32768)):
            with self.subTest(engine=engine), self.assertRaises(ValueError):
                parse_allocations(observation(), engine, count, 64)
