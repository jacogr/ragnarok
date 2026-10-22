# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Resource comparisons require admitted raw evidence, exact workloads and explicit source changes."""
import copy
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from compare_storage_resource_panels import PANELS, compare
from storage_resource_panel_fixtures import fixture


class StorageResourceComparisonTests(unittest.TestCase):
    """A plausible peak ratio cannot hide changed native work, hosts or source/build provenance."""

    def test_matching_panels_and_descriptive_peak_ratio(self):
        """Every supported report is validated before comparing its identical source-owned cases."""
        for name,module in PANELS.items():
            with self.subTest(panel=name):
                baseline = fixture(module); candidate = copy.deepcopy(baseline)
                candidate['runs'][0]['resources']['peak_rss_bytes'] = 500000
                self.assertIn('0.500',compare(name,baseline,candidate))

    def test_source_host_and_unchecked_work_refuse(self):
        """Changed sources need explicit review; dirty, foreign-host and failed-command reports refuse."""
        baseline = fixture(PANELS['lifetimes'])
        for change in (lambda r:r['inputs'].update(dirty=True), lambda r:r['hardware'].update(cpu='foreign'),
                       lambda r:r['checks'][1].update(exit_code=124), lambda r:r['runs'][0]['observed'].update(checks=1)):
            candidate = copy.deepcopy(baseline); change(candidate)
            with self.assertRaises(ValueError): compare('lifetimes',baseline,candidate)
        candidate = copy.deepcopy(baseline); name='tools/storage_lifetime_benchmark.py'
        candidate['inputs']['sources'][name] = 'e'*64
        with self.assertRaises(ValueError): compare('lifetimes',baseline,candidate)
        self.assertIn(name,compare('lifetimes',baseline,candidate,[name]))
