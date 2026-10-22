# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Larger workload reports cannot fabricate map checks, physical bounds or unavailable reopen work."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_deployment_benchmark as benchmark


def output(engine='managed', count=65536, steps=64):
    """Author complete scalar witnesses independently of the native larger-fixture implementation."""
    reopen = -1 if engine == 'memory' else 1800
    checks = count*(2 if engine == 'memory' else 3)
    return f'deployment\t{engine}\t{count}\t{steps}\t{steps+1}\t{count*2+1000}\t100\t900\t{reopen}\t900\t100\t{checks}\n'


class StorageDeploymentBenchmarkTests(unittest.TestCase):
    """Deterministic coverage and complete lifetime identity precede every descriptive resource number."""

    def test_bounded_case_plan_and_each_backend(self):
        """Both orders retain five bounded trajectories per backend; memory never acquires reopen evidence."""
        self.assertEqual(len(benchmark.CASES), 30)
        for engine in ('memory', 'journal', 'managed'):
            with self.subTest(engine=engine):
                row = benchmark.parse(output(engine), (0, engine, 65536, 64))
                self.assertEqual(row['checks'], 65536*(2 if engine == 'memory' else 3))
        self.assertEqual(benchmark.arguments((0, 'managed', 65536, 64), '/owned'), ['managed', 65536, 64, '/owned'])

    def test_missing_released_overflow_or_foreign_identity_refuses(self):
        """Malformed values and incomplete maps cannot be accepted from an otherwise successful process."""
        good = output()
        for value in (good.replace('\t900', '\tTrue'), good.replace('\t900', '\t'+str(1<<63)),
                      good.replace('\t100\t196608', '\t101\t196608'), good.replace('\t196608', '\t65536'),
                      good.replace('\t65\t', '\t64\t'), good+good):
            with self.subTest(value=value), self.assertRaises(ValueError):
                benchmark.parse(value, (0, 'managed', 65536, 64))
        with self.assertRaises(ValueError):
            benchmark.parse(good, (0, 'managed', 131072, 64))
