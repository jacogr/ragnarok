# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Guard controlled pressure planning, swap availability, scoped advice and failed publication."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import storage_resident_pressure as panel


class ResidentPressureTests(unittest.TestCase):
    """Resident limits are neither address-space ceilings nor evidence of completed paged execution."""

    def test_swap_requires_existing_free_capacity(self):
        """Absent/full swap is explicit; the runner must never create or enable host swap."""
        header = 'Filename Type Size Used Priority\n'
        self.assertFalse(panel.swap_context(header)['permitted'])
        self.assertFalse(panel.swap_context(header+'/swap file 524288 500000 -2\n')['permitted'])
        self.assertTrue(panel.swap_context(header+'/swap file 524288 0 -2\n')['permitted'])
        with self.assertRaises(ValueError):
            panel.swap_context(header+'/swap file 1 2 -2\n')

    def test_eviction_refuses_symlinked_or_foreign_namespace(self):
        """A malformed namespace cannot reach the advice syscall, even if a prior hash was valid."""
        with tempfile.TemporaryDirectory() as owned:
            target = Path(owned)/'target'
            target.write_bytes(b'fixture')
            alias = Path(owned)/'store'
            alias.symlink_to(target)
            with patch.object(panel.os, 'posix_fadvise', create=True) as advice, self.assertRaises(ValueError):
                panel.evict_owned(alias, 'journal')
            advice.assert_not_called()
            with patch.object(panel.os, 'posix_fadvise', create=True) as advice, self.assertRaises(ValueError):
                panel.evict_owned(target, 'journal')
            advice.assert_not_called()

    def test_advice_is_per_descriptor_and_preserves_bytes(self):
        """Linux-specific advice is optional in the test host but always targets one no-follow owned file."""
        with tempfile.TemporaryDirectory() as owned:
            path = Path(owned)/'store'
            path.write_bytes(b'closed fixture')
            with patch.object(panel.os, 'posix_fadvise', create=True) as advice, \
                    patch.object(panel.os, 'POSIX_FADV_DONTNEED', 4, create=True):
                rows = panel.evict_owned(path, 'journal')
            advice.assert_called_once()
            self.assertEqual(rows[0]['name'], 'store')
            self.assertEqual(path.read_bytes(), b'closed fixture')

    def test_unsupported_panel_removes_stale_success(self):
        """A failed Linux precondition must not leave last run's successful Markdown or CSV."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ('summary.md', 'observations.csv', 'results.json'):
                (root/name).write_text('stale')
            with patch.object(panel, 'preflight', side_effect=RuntimeError('unsupported')), \
                    self.assertRaises(RuntimeError):
                panel.run(root)
            self.assertFalse((root/'summary.md').exists())
            self.assertFalse((root/'observations.csv').exists())
            self.assertIn('"status": "failed"', (root/'results.json').read_text())

    def test_unavailable_is_not_zero_resource_success(self):
        """The CSV keeps unavailable metrics absent; zero denotes a real measured counter only."""
        row = dict(outcome='unavailable', backend='journal', count=131072, name='max256-swap256')
        row['pass'] = 0
        values = panel.table_row(row)
        self.assertNotIn('rss_bytes', values)
        self.assertEqual(values['outcome'], 'unavailable')

    def test_missing_process_sample_keeps_exact_kernel_and_wait4_peaks(self):
        """An exec/exit sampling gap leaves null gauges rather than hiding available exact peak evidence."""
        from test_storage_pressure_observer import snapshot
        raw = snapshot()
        raw['memory.peak'] = '8192\n'
        observed = dict(after_raw=raw, sampled_peaks=None, elapsed_seconds=1.0,
                        resources=dict(peak_rss_bytes=4096, major_faults=0, input_blocks=1),
                        evidence=dict(events=dict(high=0, oom_kill=0),
                        reclaim=dict(pgscan=0, pgsteal=0), stalls_us=dict(full=0), io={}))
        row = dict(backend='journal', count=32768, name='max128-noswap', outcome='completed',
                   native=dict(opened_bytes=2048, closed_bytes=2048, released=0),
                   execution=dict(observed=dict(runs=[observed])))
        row['pass'] = 0
        result = panel.table_row(row)
        self.assertIsNone(result['sampled_swap_bytes'])
        self.assertEqual(result['rss_bytes'], 4096)
        self.assertEqual(result['cgroup_peak_bytes'], 8192)

    def test_pressure_workflow_is_explicit_and_probe_precedes_setup(self):
        """No label, merge or unrelated performance request starts privileged pressure experiments."""
        root = Path(__file__).resolve().parents[1]
        workflow = (root/'.github/workflows/ci.yml').read_text().split('  storage-pressure:\n')[1]
        self.assertIn("github.event_name == 'workflow_dispatch' && inputs.suite == 'storage-pressure'", workflow)
        self.assertLess(workflow.index('run: make probe-storage-resident-pressure'),
                        workflow.index('run: make bench-storage-resident-pressure'))
        self.assertIn('if: always()', workflow)
        self.assertIn('build/tests/storage-resident-pressure/**/*.json', workflow)
        make = (root/'Makefile').read_text()
        self.assertIn('probe-storage-resident-pressure:\n', make)
        self.assertNotIn('probe-storage-resident-pressure: setup', make)
        self.assertIn('bench-storage-resident-pressure: setup\n', make)

    def test_plan_keeps_original_profile_and_two_real_memory_budgets(self):
        """A hard memory cgroup and a swap allowance cannot be replaced with RLIMIT_AS."""
        maximums = {bounds[1] for _, bounds in panel.TREATMENTS}
        self.assertTrue({128*panel.MIB, 256*panel.MIB, 512*panel.MIB} <= maximums)
        self.assertEqual(panel.CONTROL, (None, None, 0))
        self.assertEqual(len(panel.CASES), 4)
