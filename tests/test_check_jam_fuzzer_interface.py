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
        return dict(cases={name: dict(passed=True, build=dict(exit_code=0), run=dict(exit_code=0),
                                     expected_sha256='a'*64, actual_sha256='a'*64) for name in interface.CASES},
                    socket=dict(passed=True, guests=dict(passed=True, sessions=2, signed_imports=3,
                        guest_siblings=1, expected_state_queries=11, completed_sessions=2,
                        completed_imports=3, retained_siblings=1, complete_state_queries=11,
                        consensus_rejections=3, isolated_reconnects=1)))

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

    def test_transcript_and_native_stages_are_required(self):
        """A stale success flag cannot cover mismatched expected bytes, failed linking or failed native execution."""
        name = interface.CASES[0]
        for field, value in (('actual_sha256', 'b'*64), ('expected_sha256', ''),
                             ('build', dict(exit_code=1)), ('run', dict(exit_code=2)),
                             ('run', dict(exit_code=False)), ('run', None)):
            report = self.complete()
            report['cases'][name][field] = value
            self.assertFalse(interface.passed(report))
        report = self.complete()
        del report['cases'][name]['actual_sha256']
        self.assertFalse(interface.passed(report))

    def test_incomplete_guest_socket_work_is_required(self):
        """Partial loops, absent guest evidence and missing full-map/sibling checks fail the same aggregate gate."""
        for field in ('completed_sessions', 'completed_imports', 'retained_siblings',
                      'complete_state_queries', 'consensus_rejections', 'isolated_reconnects'):
            report = self.complete()
            report['socket']['guests'][field] -= 1
            self.assertFalse(interface.passed(report))
        report = self.complete()
        del report['socket']['guests']
        self.assertFalse(interface.passed(report))
        self.assertIn('guest socket evidence: failed or missing', interface.summary(report))

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
