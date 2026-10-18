# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check runtime family budgets, rejection verdicts and summary scope.

Exposes VerificationFailures for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import test_runtime


# Keep failures ownership and failure safeguards independent of other verification groups.
class VerificationFailures(unittest.TestCase):
    # Missing, duplicate and failed probes fail their own job without borrowing unit/corpus success.
    def test_runtime_failure_inventory(self):
        # Each data-driven family retains its independent budget; specialized workloads stay explicit.
        from failure_checks import FAILURE_SUITES
        for name, suite in FAILURE_SUITES.items():
            # A changed case list must match its separately declared family requirement.
            self.assertEqual(len(suite['cases']), test_runtime.FAILURE_COUNTS[name], name)
        self.assertEqual({name: count for name, count in test_runtime.FAILURE_COUNTS.items()
                          if name not in FAILURE_SUITES},
                         {'store': 9, 'runtime': 3, 'bandersnatch': 32, 'offload': 4,
                          'composition': 36, 'workqueues': 86, 'availability': 52})
        report = {key: [dict(name=str(index), passed=True) for index in range(count)]
                  for key, count in test_runtime.FAILURE_COUNTS.items()}
        report['store_controls'] = dict(passed=True)
        self.assertTrue(test_runtime.failures_passed(report))
        for key in test_runtime.FAILURE_COUNTS:
            # A fixed complete inventory rejects missing rows, duplicates and a failed diagnostic predicate.
            with self.subTest(group=key):
                self.assertFalse(test_runtime.failures_passed({**report, key: report[key][1:]}))
                self.assertFalse(test_runtime.failures_passed({**report, key: [report[key][0]]*len(report[key])}))
                self.assertFalse(test_runtime.failures_passed({**report, key: [dict(row, passed=False) for row in report[key]]}))
        self.assertFalse(test_runtime.failures_passed({**report, 'store_controls': dict(passed=False)}))
        self.assertFalse(test_runtime.failures_passed({**report, 'suites': []}))
        self.assertFalse(test_runtime.failures_passed({**report, 'extra_corpus': dict(passed=True)}))

    # Runtime summary rows report their actual verdicts independently of both other native jobs.
    def test_failure_summary_scope(self):
        from summarize_tests import summarize
        report = dict(status='failed', store_controls=dict(passed=False),
                      **{key: [dict(passed=False)] for key in test_runtime.FAILURE_COUNTS})
        text = summarize(report, 'failures')
        self.assertIn('| store | 0 | 1 |', text)
        self.assertIn('Store positive controls: Fail', text)
        self.assertNotIn('Native suites:', text)
        self.assertNotIn('Independent corpora:', text)
        self.assertNotIn('Compilation rejections:', text)


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
