# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject fabricated fixture release and substituted native lifetime identities."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_lifetime_benchmark as benchmark


def observation(count=8192):
    """Independent values show a live fixture followed by exact return to the starting allocator state."""
    return f'lifetime\tfixture\t{count}\t64\t{count+64}\t100\t900\t-1\t-1\t-1\t100\n'


class StorageLifetimeBenchmarkTests(unittest.TestCase):
    """Canonical values and actual scope retirement remain semantic requirements."""

    def test_fixture_release_and_bounded_plan(self):
        """Fixture-only controls have no invented repository-owner observations."""
        row = benchmark.parse(observation(), ('fixture', 8192))
        self.assertEqual(row['released'], row['baseline'])
        self.assertEqual(row['owner'], -1)
        self.assertEqual(benchmark.arguments(('fixture', 8192), '/owned'), ['fixture', 8192])

    def test_malformed_or_unreleased_fixture_refuses(self):
        """Noncanonical integers, missing scope release and extra output cannot pass on exit status alone."""
        good = observation()
        for value in (good.replace('\t900', '\t-1'), good.replace('\t100\n', '\t101\n'),
                      good.replace('\t900', '\tTrue'), good.replace('\t900', '\t'+str(1<<63)),
                      good.replace('\t900', '\t0900'), good+good):
            with self.subTest(value=value), self.assertRaises(ValueError):
                benchmark.parse(value, ('fixture', 8192))
        with self.assertRaises(ValueError):
            benchmark.parse(good, ('fixture', 32768))

    def test_isolated_owner_has_no_fixture_or_reader(self):
        """The owner-only plan requires fixture absence and exact release on close."""
        value = 'lifetime\towner\t8192\t64\t8192\t100\t-1\t900\t-1\t100\t100\n'
        self.assertEqual(benchmark.parse(value, ('owner', 8192))['owner'], 900)
        with self.assertRaises(ValueError):
            benchmark.parse(value.replace('\t900', '\t-1'), ('owner', 8192))
