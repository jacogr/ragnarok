# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate isolated child accounting without relaxing the existing speed sample coverage."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_resource_child as child
from storage_growth_report import parse_growth
from test_storage_growth_report import output
CHILD = ROOT/'tools/storage_resource_child.py'
COUNTERS = ('peak_rss_bytes', 'minor_faults', 'major_faults')


class StorageResourceChildTests(unittest.TestCase):
    """Exercise real isolated children, unit conversions and refusal to reuse previous counters."""

    def test_single_sample_cannot_replace_speed_coverage(self):
        """The resource-only one-sample plan is explicit; default speed parsing still requires thirteen."""
        single = output('memory', 8192, 64).split('publication\t8192\t64\tsweep\t1\t')[0]
        self.assertEqual(len(parse_growth(single, 'memory', 8192, 64, samples=1)), 1)
        with self.assertRaises(ValueError):
            parse_growth(single, 'memory', 8192, 64)
        for count in (True, 0, 2):
            with self.subTest(count=count), self.assertRaises(ValueError):
                parse_growth(single, 'memory', 8192, 64, samples=count)


    def test_fresh_process_observes_only_its_child(self):
        """Two real observer processes independently collect nonzero RSS and bounded fault counts."""
        with tempfile.TemporaryDirectory() as folder:
            for index in range(2):
                target = Path(folder)/f'{index}.json'
                result = subprocess.run([sys.executable, str(CHILD), str(target), sys.executable,
                                         '-c', 'payload=bytearray(8*1024*1024); print("native positive control")'],
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, 'native positive control\n')
                counters = json.loads(target.read_text())
                self.assertEqual(set(counters), set(COUNTERS))
                self.assertGreater(counters['peak_rss_bytes'], 0)
                self.assertTrue(all(type(v) is int and v >= 0 for v in counters.values()))


    def test_host_rss_units_are_normalized(self):
        """Darwin bytes and Linux KiB produce explicit byte units; unsupported hosts refuse."""
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'resource.json'
            for system, expected in (('Darwin', 7), ('Linux', 7168)):
                with self.subTest(system=system), patch.object(child.platform, 'system', return_value=system), patch.object(
                        child.subprocess, 'run', return_value=SimpleNamespace(returncode=0)), patch.object(
                        child.resource, 'getrusage', side_effect=[SimpleNamespace(ru_maxrss=0),
                            SimpleNamespace(ru_maxrss=7, ru_minflt=3, ru_majflt=0)]):
                    child.observe(['native'], target)
                    self.assertEqual(json.loads(target.read_text()),
                                     dict(peak_rss_bytes=expected, minor_faults=3, major_faults=0))
            with patch.object(child.platform, 'system', return_value='unsupported'):
                with self.assertRaisesRegex(RuntimeError, 'Unsupported'):
                    child.observe(['native'], target)
                self.assertFalse(target.exists())


    def test_used_observer_cannot_accumulate_previous_children(self):
        """An accidentally reused observer refuses before launching the native workload."""
        with tempfile.TemporaryDirectory() as folder, patch.object(child.platform, 'system', return_value='Linux'), patch.object(
                child.resource, 'getrusage', return_value=SimpleNamespace(ru_maxrss=1)), patch.object(child.subprocess, 'run') as launch:
            with self.assertRaisesRegex(RuntimeError, 'already has child'):
                child.observe(['native'], Path(folder)/'resource.json')
            launch.assert_not_called()


    def test_native_failure_removes_old_counter_artifact(self):
        """A failed native assertion cannot reuse an earlier resource observation."""
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'resources.json'; target.write_text('stale success')
            result = subprocess.run([sys.executable, str(CHILD), str(target), sys.executable,
                                     '-c', 'raise SystemExit(7)'], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(target.exists())

