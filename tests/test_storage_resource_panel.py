# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate shared resource-panel failure publication before individual panels adopt orchestration."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_resource_panel as panel


class StorageResourcePanelTests(unittest.TestCase):
    """A failed stage must retire stale success and retain the originating native diagnostic."""

    def test_failed_build_preserves_receipt(self):
        """No failed native build can leave the previous public success summary in place."""
        with tempfile.TemporaryDirectory() as folder:
            owned = Path(folder); (owned/'summary.md').write_text('old success')
            with patch.object(panel, 'installed', return_value=('compiler', None)), patch.object(panel, 'dependencies'), patch.object(
                    panel, 'build_native'), patch.object(panel, 'panel_identity', return_value={}), patch.object(
                    panel.NativeChecks, 'build', return_value=(dict(exit_code=9, command=[], log='native failed'), owned/'binary')):
                with self.assertRaisesRegex(RuntimeError, 'native failed'):
                    panel.run_panel(owned, Path('source'), (), [], lambda c, p: [], lambda r, c: {}, lambda r: 'summary')
            import json
            report = json.loads((owned/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['checks'][0]['exit_code'], 9)
            self.assertFalse((owned/'summary.md').exists())

    def test_running_or_incomplete_report_refuses(self):
        """A partial run cannot bypass raw-observation or execution coverage admission."""
        for report in ({}, {'status': 'running'}, {'status': 'checks-passed'}):
            with self.subTest(report=report), self.assertRaises(ValueError):
                panel.validate_panel(report, Path('source'), (), [], lambda c, p: [], lambda r, c: {})

    def test_extra_artifact_plan_cannot_escape_or_overwrite_report(self):
        """Caller-owned exports stay in the panel directory and cannot replace final provenance."""
        with tempfile.TemporaryDirectory() as folder:
            for name in ('../outside.csv', 'results.json', 'summary.md'):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    panel.run_panel(folder, Path('source'), (), [], lambda c, p: [], lambda r, c: {},
                                    lambda r: 'summary', artifacts=((name, lambda r: 'rows'),))

    def test_late_export_failure_retires_all_success_artifacts(self):
        """A second export refusal removes the first newly written file as well as an old summary."""
        with tempfile.TemporaryDirectory() as folder:
            owned = Path(folder); binary = owned/'binary'; binary.write_bytes(b'fixture binary')
            (owned/'summary.md').write_text('old success'); (owned/'rows.csv').write_text('old rows')
            def refuse(report):
                """The simulated exporter fails after a previous artifact was already written."""
                raise OSError('late export refused')
            with patch.object(panel, 'installed', return_value=('compiler', None)), patch.object(panel, 'dependencies'), patch.object(
                    panel, 'build_native'), patch.object(panel, 'panel_identity', return_value={}), patch.object(panel, 'validate_panel'), patch.object(
                    panel.NativeChecks, 'build', return_value=(dict(exit_code=0, command=[], log='native passed'), binary)):
                with self.assertRaisesRegex(OSError, 'late export'):
                    panel.run_panel(owned, Path('source'), (), [], lambda c, p: [], lambda r, c: {}, lambda r: 'summary',
                                    artifacts=(('rows.csv', lambda r: 'new rows'), ('second.csv', refuse)))
            self.assertFalse((owned/'summary.md').exists())
            self.assertFalse((owned/'rows.csv').exists())
            import json
            self.assertEqual(json.loads((owned/'results.json').read_text())['status'], 'failed')
