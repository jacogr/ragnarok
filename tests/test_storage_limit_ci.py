# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
from workflow_fixtures import event_context, selected_families, family_section
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
class LimitCITests(unittest.TestCase):
    """Memory ceilings remain in the existing opt-in Storage family with always-run reporting."""
    def test_group_and_failure_artifacts(self):
        """No new job or trigger is needed; missing evidence must survive the failure path."""
        root=Path(__file__).resolve().parents[1]
        workflow=(root/'.github/workflows/ci.yml').read_text()
        section=family_section(workflow, 'perf', 'bench-storage')
        family=next(row for row in selected_families(workflow, 'perf', event_context())
                    if row['group'] == 'bench-storage')
        self.assertEqual(family['minutes'],30)
        self.assertIn('run: make bench-storage-memory-ceilings\n',section)
        self.assertIn('run: make bench-storage\n',section)
        self.assertIn("if: ${{ always() && matrix.family.group == 'bench-storage' }}\n        run: make summary-storage-memory-ceilings SUMMARY_OUTPUT=\"$GITHUB_STEP_SUMMARY\"",section)
        self.assertNotIn('run: make bench-storage-memory-ceilings',
                         family_section(workflow, 'perf', 'bench-storage-growth'))
        for suffix in ('*.log','results.json','observations.csv','summary.md','status.md'):
            self.assertIn('build/tests/storage-memory-ceilings/'+suffix,section)
    def test_make_setup_boundaries(self):
        """Experiments provision native tools; summary inspection remains setup-free."""
        root=Path(__file__).resolve().parents[1];text=(root/'Makefile').read_text()
        self.assertIn('bench-storage-memory-ceilings: setup\n',text)
        self.assertIn('summary-storage-memory-ceilings:\n',text)
        self.assertNotIn('summary-storage-memory-ceilings: setup',text)
