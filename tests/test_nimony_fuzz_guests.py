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
