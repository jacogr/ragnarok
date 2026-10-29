# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prevent mismatched workloads, changed durability work and noisy evidence becoming unqualified speed claims."""
import copy
import json
import subprocess
import tempfile
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from compare_storage_benchmarks import compare_reports
from test_storage_benchmark import report_fixture


class StorageBenchmarkComparisonTests(unittest.TestCase):
    """Comparison consumes fully validated raw reports, not their stored Markdown or asserted medians."""

    def test_matching_reports_and_explicit_production_difference(self):
        a=report_fixture();b=copy.deepcopy(a);a['sources']['src/storage/node/repository.nim']='1'*64
        b['sources']['src/storage/node/repository.nim']='2'*64;b['head']='b'*40
        text=compare_reports(a,b,['src/storage/node/repository.nim'])
        self.assertIn('1.000×',text)
        self.assertIn('identical',text)
        with self.assertRaisesRegex(ValueError,'unapproved source'):
            compare_reports(a,b)

    def test_changed_workload_or_compiler_cannot_compare(self):
        a=report_fixture()
        for change in ('source','compiler','host','dirty'):
            b=copy.deepcopy(a)
            if change=='source': b['sources']['tests/performance/storage_workload.nim']='f'*64
            elif change=='compiler': b['compiler_sha256']='f'*64
            elif change=='host': b['hardware']['cpu']='another CPU'
            else: b['worktree_dirty']=True
            with self.subTest(change=change),self.assertRaises(ValueError):
                compare_reports(a,b)

    def test_selected_physical_work_and_sdk_counts_must_match(self):
        from storage_benchmark_report import aggregate
        a=report_fixture();b=copy.deepcopy(a)
        for observations in b['passes']:
            for row in observations['memory-1024-leading-16-1']:
                row['stored_nodes']+=1
        b['cases']=aggregate(b['passes'])
        with self.assertRaisesRegex(ValueError,'physical work'):
            compare_reports(a,b)
        b=copy.deepcopy(a)
        b['growth']['io']['observations']['journal-1024-64-sweep'][0]['fsync']+=1
        with self.assertRaisesRegex(ValueError,'SDK work'):
            compare_reports(a,b)

    def test_failed_cli_clears_old_result_and_protects_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);a=folder/'baseline.json';b=folder/'candidate.json';out=folder/'comparison.md'
            report=report_fixture();a.write_text(json.dumps(report));bad=copy.deepcopy(report);bad['compiler_sha256']='f'*64
            b.write_text(json.dumps(bad));out.write_text('old successful comparison')
            command=[sys.executable,str(ROOT/'tools/compare_storage_benchmarks.py'),'--baseline',str(a),'--candidate',str(b),'--output']
            result=subprocess.run([*command,str(out)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(out.exists())
            before=a.read_bytes();result=subprocess.run([*command,str(a)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(a.read_bytes(),before)

    def test_forged_statistics_are_revalidated(self):
        a=report_fixture();b=copy.deepcopy(a);b['growth']['cases'][0]['engines']['memory']['median_ns']=1
        with self.assertRaises(ValueError):
            compare_reports(a,b)


if __name__=='__main__':
    unittest.main()
