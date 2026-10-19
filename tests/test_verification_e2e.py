# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check E2E workload completeness and disjoint suite ownership.

Exposes VerificationE2E for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_e2e
from native_tests import UNIT_SUITES


# Keep e2e ownership and failure safeguards independent of other verification groups.
class VerificationE2E(unittest.TestCase):
    # Every E2E workload and CLI selftest is required, including on a fresh standalone invocation.
    def test_e2e_complete_inventory(self):
        report = dict(suites=[dict(name=name, passed=True) for name in test_e2e.SELFTESTS],
                      **{name: dict(passed=True) for name in test_e2e.WORKLOADS})
        self.assertTrue(test_e2e.passed(report))
        for name in test_e2e.WORKLOADS:
            # A successful sibling cannot stand in for a missing or failed lifecycle.
            with self.subTest(workload=name):
                missing = dict(report)
                del missing[name]
                self.assertFalse(test_e2e.passed(missing))
                missing[name] = dict(passed=False)
                self.assertFalse(test_e2e.passed(missing))
        self.assertFalse(test_e2e.passed({**report, 'suites': []}))
        self.assertFalse(test_e2e.passed({**report, 'suites': report['suites']+[report['suites'][0]]}))
        self.assertFalse(test_e2e.passed({**report, 'suites': [dict(name='replacement', passed=True)]+report['suites'][1:]}))
        self.assertFalse(set(UNIT_SUITES) & set(test_e2e.SELFTESTS))


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
