# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject incomplete or incomparable memory evidence before publishing descriptive reopen ratios."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import compare_storage_reopens as comparison
import storage_fresh_reopen as reopen
import storage_lifetime_benchmark
from storage_resource_panel_fixtures import fixture as panel_fixture
from storage_benchmark import source_hashes


def fixture():
    """Author all native witnesses and exact commands while reusing only shared inert build identities."""
    base = panel_fixture(storage_lifetime_benchmark)
    inputs = copy.deepcopy(base['inputs'])
    inputs['sources'].update(source_hashes([reopen.SOURCE]))
    build = copy.deepcopy(base['checks'][0])
    build['command'] = [v for v in build['command'] if not v.startswith('-d:') or v == '-d:release']
    build['command'][-1] = str(reopen.SOURCE)
    binary = '/fixture/panel-native'
    report = dict(status='checks-passed', schema_version=2, inputs=inputs,
                  native_binary_sha256='a'*64, environment=base['environment_start'],
                  checks=[build], rows=[])
    for index, (engine, count) in enumerate(reopen.CASES):
        # Complete-map/root/lifetime assertions are represented independently of the comparison renderer.
        root = 'a'*64; owned = '/fixture/reopen-'+str(index)
        prepared = f'prepared\t{engine}\t{count}\t16\t17\t{root}'
        raw = f'reopened\t{engine}\t{count}\t16\t17\t{root}\t{count*2}\t100\t1000\t800\t100\t{count*2}'
        observed = dict(stored_nodes=count*2, baseline=100, opened_bytes=1000, closed_bytes=800,
                        released=100, checks=count*2)
        names = ('store',) if engine == 'journal' else ('CURRENT', 'LOCK', 'journal-0000000000000001.wal',
                                                       'snapshot-0000000000000001.bin')
        selected = {name:'d'*64 for name in names}
        report['rows'].append(dict(case=[engine,count], root=root, prepared_raw=prepared, raw=raw,
                                   observed=observed, selected_before=selected,
                                   selected_after=copy.deepcopy(selected),
                                   resources=dict(peak_rss_bytes=1000000, minor_faults=7, major_faults=0)))
        for suffix, command in [('prepare',[binary,'prepare',engine,str(count),owned]),
                                ('open',[sys.executable,str(reopen.CHILD),owned+'/resources.json',binary,
                                         'open',engine,str(count),owned,root])]:
            report['checks'].append(dict(command=command, exit_code=0, elapsed_seconds=0.01,
                                         log=f'{suffix}-{index}.log'))
    return report


class ReopenComparisonTests(unittest.TestCase):
    """Only matching full native plans and approved source changes can produce a descriptive memory table."""

    def test_matching_reports_and_explicit_source_change(self):
        before = fixture(); after = copy.deepcopy(before)
        name = 'src/storage/managed_io.nim'
        after['inputs']['sources'][name] = 'f'*64
        after['rows'][0]['resources']['peak_rss_bytes'] = 500000
        with self.assertRaisesRegex(ValueError, 'Unapproved'):
            comparison.compare(before, after)
        text = comparison.compare(before, after, [name])
        self.assertIn('0.500', text)
        self.assertIn('omit CPU/OS', text)
        self.assertIn('not a speedup', text)

    def test_build_environment_workload_and_inventory_drift_refuse(self):
        before = fixture()
        for field in ('compiler','environment','workload','inventory'):
            # An allowlist cannot authorize different counters, native workload or undeclared input inventory.
            after = copy.deepcopy(before)
            if field == 'compiler': after['inputs']['compiler_sha256'] = 'f'*64
            elif field == 'environment': after['environment']['device_id'] += 1
            elif field == 'workload': after['inputs']['sources'][comparison.FIXED_WORKLOAD[0]] = 'f'*64
            else: after['inputs']['sources']['src/storage/extra.nim'] = 'f'*64
            with self.subTest(field=field), self.assertRaises(ValueError):
                comparison.compare(before, after, [comparison.FIXED_WORKLOAD[0]])

    def test_raw_control_and_counter_substitutions_refuse(self):
        before = fixture()
        for field in ('root','rows','rss','dirty'):
            after = copy.deepcopy(before)
            if field == 'root': after['rows'][0]['raw'] = after['rows'][0]['raw'].replace('a'*64,'b'*64)
            elif field == 'rows': after['rows'].pop()
            elif field == 'rss': after['rows'][0]['resources']['peak_rss_bytes'] = True
            else: after['inputs']['dirty'] = True
            with self.subTest(field=field), self.assertRaises(ValueError):
                comparison.compare(before, after)

    def test_namespace_and_actual_physical_work_must_match(self):
        before = fixture(); after = copy.deepcopy(before)
        key = next(iter(after['rows'][0]['selected_before']))
        after['rows'][0]['selected_before'][key] = 'f'*64
        after['rows'][0]['selected_after'][key] = 'f'*64
        with self.assertRaisesRegex(ValueError, 'physical work'):
            comparison.compare(before, after)
        after = copy.deepcopy(before); row = after['rows'][0]
        row['observed']['stored_nodes'] += 1
        values = row['raw'].split('\t'); values[6] = str(row['observed']['stored_nodes'])
        row['raw'] = '\t'.join(values)
        with self.assertRaisesRegex(ValueError, 'physical work'):
            comparison.compare(before, after)

    def test_failed_cli_clears_stale_output_and_protects_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            # Reports remain inert data; no fixture compiler or native command exists to execute.
            folder = Path(temporary); before = folder/'before.json'; after = folder/'after.json'
            baseline = fixture(); candidate = copy.deepcopy(baseline); candidate['inputs']['dirty'] = True
            before.write_text(json.dumps(baseline)); after.write_text(json.dumps(candidate))
            output = folder/'comparison.md'; output.write_text('old success')
            command = [sys.executable,str(ROOT/'tools/compare_storage_reopens.py'),
                       '--baseline',str(before),'--candidate',str(after),'--output']
            result = subprocess.run([*command,str(output)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0); self.assertFalse(output.exists())
            original = before.read_bytes()
            result = subprocess.run([*command,str(before)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0); self.assertEqual(before.read_bytes(),original)

    def test_bound_precedes_json_parsing(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)/'report.json'; source.write_bytes(b'x'*11)
            with patch.object(comparison,'MAX_REPORT_BYTES',10), self.assertRaisesRegex(ValueError,'exceeds'):
                comparison.read_report(source)


if __name__ == '__main__':
    unittest.main()
