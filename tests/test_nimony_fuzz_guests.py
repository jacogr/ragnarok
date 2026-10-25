# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Real-entry guest socket plans preserve independent complete-map and explicit-profile evidence."""
import unittest
from nimony_fuzz_guests import prepare_sessions
from jam_fuzzer_guest_reference import host_parameters
from state_layout_oracle import digest


class GuestSocketEvidence(unittest.TestCase):
    """Freeze guest/fork/checkpoint plan completeness before the target starts."""

    def test_whole_map_socket_plan(self):
        """The real socket workload includes all130 authored imports,15 siblings and35 fresh sessions."""
        jobs, evidence = prepare_sessions(host_parameters())
        self.assertEqual(evidence['signed_imports'], 130)
        self.assertEqual(evidence['guest_siblings'], 15)
        self.assertEqual(evidence['sessions'], 35)
        self.assertEqual(len(evidence['references']), 4)
        for job in jobs:
            self.assertTrue(job['steps'])
            self.assertEqual(job['initialize'][1:298], job['header'])
            self.assertEqual(job['steps'][0]['block'][:32], digest(job['header']))
            self.assertEqual(job['steps'][0]['block'][32:64], job['state'][:32])

    def test_unrelated_host_profile_is_refused(self):
        """The workload cannot infer a deposit/code profile from arbitrary seed data."""
        for parameters in (host_parameters(code_limit=4096), host_parameters(deposits=(7, 1, 100)), b''):
            with self.assertRaises(AssertionError):
                prepare_sessions(parameters)

    def test_marker_headers_and_explicit_profiles(self):
        """A present epoch marker retains its complete sealed identity; undeclared profile cardinality refuses locally."""
        import hashlib
        from pathlib import Path
        import tempfile
        from types import SimpleNamespace
        from unittest.mock import patch
        from header_oracle import example, wire as header_wire
        from current_stf_oracle import checkpoint
        from state_layout_oracle import chapter_key
        from nimony_fuzz_guests import reference_sessions
        from native_fixture_contracts import FIXTURE_CONTRACTS
        from jam_minifuzz_trace import exchanges
        header = header_wire('H', example('H'))
        self.assertGreater(len(header), 297)
        state = checkpoint([(chapter_key(1), b'\0')]).hex()
        lines = ['P '+state, 'B '+(header+bytes(7)).hex(), 'O '+state]
        with tempfile.TemporaryDirectory() as folder:
            fixture = Path(folder)/'reference.json'
            fixture.write_text('{}\n')
            reference = SimpleNamespace(FIXTURE=fixture, expected_observations=lambda: ([], lines, {}))
            contract = ('TEST_REFERENCE', fixture, [(fixture, hashlib.sha256(fixture.read_bytes()).hexdigest())])
            with patch.dict(FIXTURE_CONTRACTS, test_reference=contract):
                profile = host_parameters(code_limit=4096, deposits=(7, 1, 100))
                jobs, _ = reference_sessions(reference, 'test_reference', [profile])
                self.assertEqual(jobs[0]['parameters'], profile)
                self.assertEqual(jobs[0]['steps'][0]['header'], header)
                self.assertIn(b'\x04'+digest(header), [request for request, _ in exchanges(jobs[0])])
                with self.assertRaises(AssertionError): reference_sessions(reference, 'test_reference', [])
                with self.assertRaises(AssertionError): reference_sessions(reference, 'test_reference', [b''])
