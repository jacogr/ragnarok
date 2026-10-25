# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""The opt-in JAM interface group fails closed and never claims live engine campaign validation."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import check_jam_fuzzer_interface as interface
from corpus_state import CORPORA
from workflow_fixtures import job_section


class JamInterfaceCI(unittest.TestCase):
    """Check completeness, stale-report retirement and independently gated CI matrix families."""

    def complete(self):
        """A complete synthetic verdict includes every source-owned interface case and real-entry workload."""
        return dict(cases={name: dict(passed=True) for name in interface.CASES}, socket=dict(passed=True))

    def test_every_declared_child_is_required(self):
        """No missing, extra or failed case can hide behind another successful child."""
        self.assertEqual(interface.CASES, tuple(sorted(name for name in CORPORA.tasks if name.startswith('jam_fuzzer_'))))
        self.assertTrue(interface.CASES)
        self.assertTrue(interface.passed(self.complete()))
        for name in interface.CASES:
            report = self.complete()
            del report['cases'][name]
            self.assertFalse(interface.passed(report))
            report = self.complete()
            report['cases'][name]['passed'] = False
            self.assertFalse(interface.passed(report))
        report = self.complete()
        report['cases']['undeclared'] = dict(passed=True)
        self.assertFalse(interface.passed(report))
        report = self.complete()
        del report['socket']
        self.assertFalse(interface.passed(report))

    def test_failed_setup_replaces_old_success(self):
        """An interrupted prerequisite writes a fresh failed report and explicit pending-engine summary."""
        with tempfile.TemporaryDirectory() as folder:
            build = Path(folder)
            (build/'results.json').write_text(json.dumps(self.complete()))
            with patch.object(interface, 'BUILD', build), patch.object(interface, 'installed', side_effect=OSError('fixture prerequisite failure')), patch.object(interface, 'announce'):
                self.assertEqual(interface.main(), 1)
            report = json.loads((build/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertFalse(interface.passed(report))
            self.assertEqual(report['engine_validation'], 'pending')
            self.assertIn('pending compatible polkajam-fuzz engine', (build/'summary.md').read_text())

    def test_matrix_keeps_campaign_and_interface_distinct(self):
        """PVM-only dispatch excludes the interface; both opt-in families keep their own commands and artifacts."""
        text = (interface.ROOT/'.github/workflows/ci.yml').read_text()
        job = job_section(text, 'pvm-fuzz')
        for value in ("inputs.suite == 'fuzz-pvm'", '"name":"JAM"', "matrix.family.group == 'jam-interface'", 'run: make check-jam-fuzzer-interface', 'run: make fuzz-pvm-upstream', 'jam-fuzzer-interface-${{ github.run_attempt }}'):
            self.assertIn(value, job)
        self.assertIn("if: matrix.family.group == 'pvm'", job)
        self.assertIn('fail-fast: false', job)
        self.assertIn('needs: [pvm-fuzz]', job_section(text, 'fuzz-status'))
        self.assertNotIn('continue-on-error', job)
        make = (interface.ROOT/'Makefile').read_text()
        self.assertIn('check-jam-fuzzer-interface: setup check-inventory', make)
