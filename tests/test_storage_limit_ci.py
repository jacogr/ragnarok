# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
class LimitCITests(unittest.TestCase):
    """Memory ceilings remain in the existing opt-in storage job with always-run reporting."""
    def test_group_and_failure_artifacts(self):
        """No new job or trigger is needed; missing evidence must survive the failure path."""
        root=Path(__file__).resolve().parents[1]
        section=(root/'.github/workflows/ci.yml').read_text().split('  bench-storage:\n',1)[1]
        self.assertIn('timeout-minutes: 30',section)
        self.assertIn('run: make bench-storage-memory-ceilings\n',section)
        self.assertIn('run: make bench-storage\n',section)
        self.assertIn('if: always()\n        run: make summary-storage-memory-ceilings SUMMARY_OUTPUT="$GITHUB_STEP_SUMMARY"',section)
        for suffix in ('*.log','results.json','observations.csv','summary.md','status.md'):
            self.assertIn('build/tests/storage-memory-ceilings/'+suffix,section)
    def test_make_setup_boundaries(self):
        """Experiments provision native tools; summary inspection remains setup-free."""
        root=Path(__file__).resolve().parents[1];text=(root/'Makefile').read_text()
        self.assertIn('bench-storage-memory-ceilings: setup\n',text)
        self.assertIn('summary-storage-memory-ceilings:\n',text)
        self.assertNotIn('summary-storage-memory-ceilings: setup',text)
