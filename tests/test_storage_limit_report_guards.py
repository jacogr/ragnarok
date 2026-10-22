# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from copy import deepcopy
import csv
import io
from storage_limit_report_fixtures import fixture
from storage_limit_report import validate
from storage_limit_render import counts,render
from storage_limit_csv import export
from compare_storage_memory_ceilings import compare
from summarize_storage_limits import summarize
import tempfile

class LimitReportGuardTests(unittest.TestCase):
    """Complete reports bind probes, native roots, command order, sources and byte preservation."""
    @classmethod
    def setUpClass(cls):
        """Build each inert source inventory once, then mutate independent copies per case."""
        cls.darwin=fixture();cls.linux=fixture('Linux')
    def test_complete_host_outcomes(self):
        """Unsupported Linux enforcement is not hidden behind passing native controls."""
        self.assertEqual(len(validate(self.darwin)),4);self.assertEqual(len(validate(self.linux)),4)
        self.assertEqual(counts(self.darwin),dict(controls=8,completed_caps=0,unavailable_caps=12,nonzero_caps=0,signal_caps=0))
        self.assertEqual(counts(self.linux),dict(controls=8,completed_caps=4,unavailable_caps=0,nonzero_caps=4,signal_caps=4))
    def test_report_and_probe_tampering(self):
        """Status, field aliases, coverage and probe raw/output substitution are rejected."""
        edits=[lambda r:r.update(status='collected'),lambda r:r.update(schema_version=True),lambda r:r['probes'].pop(),
               lambda r:r['rows'].pop(),lambda r:r['checks'].reverse(),lambda r:r['probes'][0]['observed'].update(status='enforced'),
               lambda r:r['probes'][0]['check']['command'].append('--fake'),lambda r:r['identity']['inputs']['sources'].clear(),
               lambda r:r['identity'].update(native_binary_sha256='bad')]
        for edit in edits:
            row=deepcopy(self.darwin);edit(row)
            with self.subTest(edit=edit),self.assertRaises(ValueError):
                validate(row)
    def test_native_identity_and_namespace_tampering(self):
        """Successful counters cannot conceal foreign roots, changed bytes or failing final controls."""
        edits=[lambda r:r['rows'][0].update(root='f'*64),lambda r:r['rows'][0]['attempts'].pop(),
               lambda r:r['rows'][0]['attempts'][0]['selected_after'].update(store='f'*64),
               lambda r:r['rows'][0]['attempts'][0]['native'].update(checks=1),
               lambda r:r['rows'][0]['attempts'][0]['execution']['observation'].update(exit_code=7),
               lambda r:r['rows'][0]['attempts'][0]['execution'].update(receipt_path='/other/receipt'),
               lambda r:r['rows'][0]['attempts'][1].update(outcome='completed')]
        for edit in edits:
            row=deepcopy(self.darwin);edit(row)
            with self.subTest(edit=edit),self.assertRaises(ValueError):
                validate(row)
    def test_linux_refusal_is_not_native_success(self):
        """No successful native payload may be attached to a signalled or refused process."""
        for index in (1,2):
            row=deepcopy(self.linux);row['rows'][0]['attempts'][index]['native']=row['rows'][0]['attempts'][0]['native']
            with self.assertRaises(ValueError):
                validate(row)
    def test_render_csv_and_missing_summary(self):
        """Unavailable cells remain literal and setup-free summaries refuse missing evidence."""
        text=render(self.darwin);self.assertIn('unavailable caps: 12',text)
        rows=list(csv.DictReader(io.StringIO(export(self.darwin))))
        self.assertEqual(len(rows),20);self.assertEqual(rows[1]['peak_rss_bytes'],'unavailable')
        with tempfile.TemporaryDirectory() as folder:
            text,failed=summarize(Path(folder)/'missing.json');self.assertTrue(failed)
    def test_matching_comparison_and_refusal(self):
        """Only identical clean provenance and matching outcomes can be compared descriptively."""
        self.assertIn('no subtraction',compare(self.darwin,self.darwin))
        edits=[lambda r:r['identity']['inputs'].update(dirty=True),lambda r:r['identity']['host'].update(cpu='other'),
               lambda r:r['identity']['inputs']['sources'].update({'tools/storage_limit_budget.py':'f'*64}),
               lambda r:r['environment'].update(device_id=999999),lambda r:r['identity'].update(native_binary_sha256='f'*64)]
        for edit in edits:
            row=deepcopy(self.darwin);edit(row)
            with self.subTest(edit=edit),self.assertRaises(ValueError):
                compare(self.darwin,row)
