# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check runtime family budgets, rejection verdicts and summary scope.

Exposes VerificationFailures for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import io
import sys
import unittest
from unittest.mock import patch

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
        report = {key: [dict(identity, passed=True) for identity in cases]
                  for key, cases in test_runtime.FAILURE_PLANS.items()}
        report['probe_cases'] = {family: dict(passed=True) for family in test_runtime.SPECIAL_DRIVERS}
        report['store_controls'] = dict(passed=True)
        self.assertTrue(test_runtime.failures_passed(report))
        for key in test_runtime.FAILURE_COUNTS:
            # A fixed complete inventory rejects missing rows, duplicates and a failed diagnostic predicate.
            with self.subTest(group=key):
                self.assertFalse(test_runtime.failures_passed({**report, key: report[key][1:]}))
                self.assertFalse(test_runtime.failures_passed({**report, key: [report[key][0]]*len(report[key])}))
                self.assertFalse(test_runtime.failures_passed({**report, key: [dict(row, passed=False) for row in report[key]]}))
                replaced = [dict(row) for row in report[key]]
                replaced[0] = dict(name='unexpected-replacement', passed=True)
                self.assertFalse(test_runtime.failures_passed({**report, key: replaced}))
        self.assertFalse(test_runtime.failures_passed({**report, 'store_controls': dict(passed=False)}))
        self.assertFalse(test_runtime.failures_passed({**report, 'probe_cases': {}}))
        self.assertFalse(test_runtime.failures_passed({**report, 'suites': []}))
        self.assertFalse(test_runtime.failures_passed({**report, 'extra_corpus': dict(passed=True)}))

    # Source-derived partitions cover every existing family once, with specialized controls assigned once.
    def test_failure_partition_coverage(self):
        from failure_plans import failure_partition, parse_failure_shard, failure_libraries, SPECIAL_CASES
        from failure_checks import FAILURE_SUITES
        for count in range(1, 5):
            # Growing the discovered family tree must need no edit to the CI scheduler.
            partitions = [failure_partition((index, count)) for index in range(1, count+1)]
            names = [family for plans, _ in partitions for family in plans]
            self.assertEqual(len(names), len(set(names)))
            self.assertEqual(set(names), set(test_runtime.FAILURE_PLANS))
            self.assertEqual(sum(specialized for _, specialized in partitions), 1)
            sizes = [len(set(plans).intersection(FAILURE_SUITES)) for plans, _ in partitions]
            self.assertLessEqual(max(sizes)-min(sizes), 1)
            for index, (plans, specialized) in enumerate(partitions, 1):
                # Controls and real native providers remain attached to the scope that consumes them.
                self.assertEqual(bool(set(plans).intersection(SPECIAL_CASES)), index == count)
                required = failure_libraries((index, count))
                if specialized:
                    self.assertIsNone(required)
                else:
                    for family in plans:
                        suite = FAILURE_SUITES[family]
                        self.assertTrue(set(suite.get('native_libraries', ())) <= required)
                        for key in ('crypto_library', 'quic_library'):
                            if suite.get(key) is not None:
                                self.assertIn(suite[key], required)
        self.assertEqual(failure_partition(), failure_partition((1, 1)))
        self.assertEqual(parse_failure_shard('2/4'), (2, 4))
        for value in ['0/4', '1/5', '2/1', 'one/4', '1', '1/4/4']:
            # A malformed partition cannot quietly fall back to a smaller passing workload.
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse_failure_shard(value)
        for value in [(True, 4), (1,), '1/4']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                failure_partition(value)

    # Partial success cannot hide missing/replaced probes, sibling results or missing specialized controls.
    def test_failure_partition_verdicts(self):
        from failure_plans import failure_partition
        for index in range(1, 5):
            # Each shard has a predeclared identity plan independent of observed process success.
            plans, specialized = failure_partition((index, 4))
            report = dict(failure_shard=[index, 4], **{key: [dict(identity, passed=True) for identity in cases]
                                                    for key, cases in plans.items()})
            if specialized:
                report.update(store_controls=dict(passed=True),
                              probe_cases={family: dict(passed=True) for family in test_runtime.SPECIAL_DRIVERS})
            self.assertTrue(test_runtime.failures_passed(report))
            for key in plans:
                # Every family retains exact completeness and positive failure verdict requirements.
                self.assertFalse(test_runtime.failures_passed({**report, key: report[key][1:]}))
                self.assertFalse(test_runtime.failures_passed({**report, key: [report[key][0]]*len(report[key])}))
                self.assertFalse(test_runtime.failures_passed({**report, key: [dict(row, passed=False) for row in report[key]]}))
            foreign = next(key for key in test_runtime.FAILURE_PLANS if key not in plans)
            self.assertFalse(test_runtime.failures_passed({**report, foreign: []}))
            self.assertFalse(test_runtime.failures_passed({**report, 'failure_shard': [0, 4]}))
            self.assertFalse(test_runtime.failures_passed({**report, 'suites': []}))
            self.assertFalse(test_runtime.failures_passed({**report, 'extra_corpus': dict(passed=True)}))
            if specialized:
                # Declared cases and store positive controls cannot be replaced by ordinary negative probes.
                self.assertFalse(test_runtime.failures_passed({**report, 'store_controls': dict(passed=False)}))
                self.assertFalse(test_runtime.failures_passed({**report, 'probe_cases': {}}))
            else:
                self.assertFalse(test_runtime.failures_passed({**report, 'store_controls': dict(passed=True)}))

    # Non-owning partitions return after their ordinary probes without looking up specialized native resources.
    def test_ordinary_partition_execution_scope(self):
        plans, _ = test_runtime.failure_partition((1, 4))
        with patch.object(test_runtime, 'run_failure_suites') as run:
            test_runtime.run_failures(Path('/fixture/nimony'), {}, {}, None, None, (1, 4))
        self.assertEqual(run.call_args.kwargs['groups'], tuple(plans))

    # Contract-only selection must be rejected before setup when passed to the unit group.
    def test_failure_partition_cli_rejection(self):
        with patch.object(sys, 'argv', ['test_runtime.py', '--compiler', '/fixture/nimony',
                                       '--failure-shard', '1/4']), patch('sys.stderr', new_callable=io.StringIO), patch.object(
                test_runtime, 'NativeChecks') as checks:
            with self.assertRaises(SystemExit) as stopped:
                test_runtime.main()
            self.assertEqual(stopped.exception.code, 2)
            checks.assert_not_called()

    # Summaries identify the shard and only claim positive controls for their actual owner.
    def test_failure_partition_summary(self):
        from summarize_tests import summarize
        for index in range(1, 5):
            plans, specialized = test_runtime.failure_partition((index, 4))
            report = dict(failure_shard=[index, 4], status='checks-passed',
                          **{family: [dict(passed=True)] for family in plans})
            if specialized:
                report['store_controls'] = dict(passed=True)
            text = summarize(report, 'failures')
            self.assertIn(f'shard {index}/4', text)
            self.assertEqual('Store positive controls:' in text, specialized)

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
