# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent speed/growth jobs must execute and validate only their complete owned evidence."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from test_storage_benchmark import native_stub, report_fixture
from storage_benchmark_report import summarize_benchmark
from compare_storage_benchmarks import compare_reports


def scoped_report(panel):
    """Derive isolated reports from complete authored matrices without inventing missing observations."""
    report=report_fixture();report['panel']=panel
    if panel=='comparison':
        # Short-only success cannot imply that growth ran in the same job.
        del report['growth']
    else:
        # The sustained matrix retains its own checked build and native binary identity.
        report.update(passes=[],cases=[],checks=[])
        del report['native_binary_sha256']
    return report


class StorageBenchmarkScopeTests(unittest.TestCase):
    """A job's scope controls execution, source freezing, failure reporting and comparisons together."""

    def test_comparison_never_executes_growth(self):
        with tempfile.TemporaryDirectory() as temporary,native_stub(Path(temporary)) as runner:
            with patch.object(runner,'run_growth',side_effect=AssertionError('unexpected growth')):
                runner.run('comparison')
            report=json.loads((Path(temporary)/'results.json').read_text())
            self.assertEqual(report['status'],'checks-passed')
            self.assertNotIn('growth',report)
            self.assertEqual(len(report['checks']),97)
            self.assertTrue((Path(temporary)/'samples.csv').is_file())

    def test_growth_never_builds_or_executes_short_comparison(self):
        with tempfile.TemporaryDirectory() as temporary,native_stub(Path(temporary)) as runner:
            with patch.object(runner.NativeChecks,'build',side_effect=AssertionError('unexpected short build')):
                runner.run('growth')
            report=json.loads((Path(temporary)/'results.json').read_text())
            self.assertEqual(report['status'],'checks-passed')
            self.assertEqual(report['passes'],[])
            self.assertEqual(report['checks'],[])
            self.assertEqual(report['growth']['status'],'checks-passed')
            self.assertFalse((Path(temporary)/'samples.csv').exists())
            self.assertIn('Sustained',(Path(temporary)/'summary.md').read_text())

    def test_each_scope_rejects_substituted_other_scope_evidence(self):
        for panel in ('comparison','growth'):
            # Metadata cannot turn stale or partial evidence into another job's successful table.
            report=scoped_report(panel)
            summarize_benchmark(report)
            report['growth' if panel=='comparison' else 'native_binary_sha256']={} if panel=='comparison' else 'a'*64
            with self.subTest(panel=panel),self.assertRaises(ValueError):
                summarize_benchmark(report)

    def test_growth_requires_complete_raw_matrix_and_io(self):
        for field in ('passes','io'):
            report=scoped_report('growth');report['growth'][field]=None
            with self.subTest(field=field),self.assertRaises((ValueError,TypeError)):
                summarize_benchmark(report)

    def test_growth_failure_removes_stale_public_success(self):
        with tempfile.TemporaryDirectory() as temporary,native_stub(Path(temporary)) as runner:
            folder=Path(temporary)
            (folder/'summary.md').write_text('old success')
            (folder/'samples.csv').write_text('old samples')
            with patch.object(runner,'run_growth',side_effect=RuntimeError('growth refused')):
                with self.assertRaisesRegex(RuntimeError,'growth refused'):
                    runner.run('growth')
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
            self.assertFalse((folder/'samples.csv').exists())
            self.assertIn('Status: failed',(folder/'summary.md').read_text())

    def test_comparisons_require_identical_scope(self):
        for panel in ('comparison','growth'):
            report=scoped_report(panel)
            self.assertIn('1.000×',compare_reports(report,copy.deepcopy(report)))
        with self.assertRaisesRegex(ValueError,'panel scope'):
            compare_reports(scoped_report('comparison'),scoped_report('growth'))


if __name__=='__main__':
    unittest.main()
