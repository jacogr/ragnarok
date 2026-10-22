# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Require allocator panels to bind one-sample native plans without fabricating unavailable boundaries."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_allocation_benchmark as benchmark
from test_storage_allocation_report import observation


class StorageAllocationBenchmarkTests(unittest.TestCase):
    """Public plan, native parser and explicit backend order stay linked."""

    def test_case_plan_is_bounded_and_reversed(self):
        """Both extents appear once per backend in each opposite-order pass."""
        self.assertEqual(len(benchmark.CASES), 12)
        self.assertEqual([c[1] for c in benchmark.CASES[:6:2]], ['memory', 'journal', 'managed'])
        self.assertEqual([c[1] for c in benchmark.CASES[6::2]], ['managed', 'journal', 'memory'])
        self.assertEqual(benchmark.arguments((0, 'managed', 8192), '/owned'), ['managed', 8192, 64, '/owned', 1, 'sweep'])

    def test_native_observations_bind_case(self):
        """A complete counter prefix still requires the requested native extent and backend."""
        value = benchmark.parse(observation(), (0, 'managed', 8192))
        self.assertEqual(value['allocations'][0]['phase'], 'fixture')
        with self.assertRaises(ValueError):
            benchmark.parse(observation(), (0, 'managed', 32768))
