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
                        consensus_rejections=3, isolated_reconnects=1)),
                    minifuzz=dict(passed=True, false_success_control=True, planned_sessions=2,
                        completed_sessions=2, planned_exchanges=9, completed_exchanges=9, signed_imports=3,
                        planned_local_missing_evidence=1, completed_local_missing_evidence=1,
                        planned_stream_recoveries=15, completed_stream_recoveries=15,
                        planned_host_profiles=2, completed_host_profiles=2, host_profiles=[
                            dict(passed=True, false_success_control=True, parameters_sha256='a'*64, local_missing_evidence=1, stream_recoveries=15, completed_sessions=1, completed_exchanges=4),
                            dict(passed=True, false_success_control=True, parameters_sha256='b'*64, local_missing_evidence=0, stream_recoveries=0, completed_sessions=1, completed_exchanges=5)]))

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

    def test_upstream_replay_cannot_be_skipped(self):
        """A zero upstream exit or outer success flag cannot replace all observed exchanges and the mismatch control."""
        report = self.complete()
        del report['minifuzz']
        self.assertFalse(interface.passed(report))
        for field, value in (('completed_sessions', 1), ('completed_exchanges', 8),
                             ('false_success_control', False), ('signed_imports', 0)):
            report = self.complete()
            report['minifuzz'][field] = value
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

    def test_minifuzz_profile_completeness(self):
        """A dropped, duplicated, partial or unverified target profile cannot pass aggregate CI evidence."""
        import copy
        good = self.complete()['minifuzz']
        self.assertTrue(interface.minifuzz_verified(good))
        for mutation in ('missing', 'duplicate', 'control', 'partial', 'count'):
            row = copy.deepcopy(good)
            if mutation == 'missing': row['host_profiles'].pop()
            elif mutation == 'duplicate': row['host_profiles'][1]['parameters_sha256'] = 'a'*64
            elif mutation == 'control': row['host_profiles'][0]['false_success_control'] = False
            elif mutation == 'partial': row['host_profiles'][0]['completed_exchanges'] -= 1
            else: row['completed_host_profiles'] -= 1
            self.assertFalse(interface.minifuzz_verified(row))

    def test_local_missing_evidence_completeness(self):
        """Missing, partial, negative or substituted local-refusal counts cannot satisfy the declared process plan."""
        import copy
        good = self.complete()['minifuzz']
        for mutation in ('missing', 'partial', 'negative', 'substituted', 'invalid-profile'):
            row = copy.deepcopy(good)
            if mutation == 'missing': del row['completed_local_missing_evidence']
            elif mutation == 'partial': row['completed_local_missing_evidence'] = 0
            elif mutation == 'negative': row['planned_local_missing_evidence'] = -1
            elif mutation == 'substituted': row['host_profiles'][0]['local_missing_evidence'] = 0
            else: row['host_profiles'][0] = None
            self.assertFalse(interface.minifuzz_verified(row))
        # Profiles with no declared local-evidence cases still require explicit matching zero observations.
        good['planned_local_missing_evidence'] = good['completed_local_missing_evidence'] = 0
        good['host_profiles'][0]['local_missing_evidence'] = 0
        self.assertTrue(interface.minifuzz_verified(good))

    def test_stream_recovery_completeness(self):
        """A skipped or substituted stream recovery cannot be hidden by complete upstream replay counts."""
        import copy
        for mutation in ('missing','partial','negative','substituted'):
            row = copy.deepcopy(self.complete()['minifuzz'])
            if mutation == 'missing': del row['completed_stream_recoveries']
            elif mutation == 'partial': row['completed_stream_recoveries'] -= 1
            elif mutation == 'negative': row['planned_stream_recoveries'] = -1
            else: row['host_profiles'][0]['stream_recoveries'] -= 1
            self.assertFalse(interface.minifuzz_verified(row))
