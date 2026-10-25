# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map STF answers become exact fuzz inputs without native-output feedback."""
from types import SimpleNamespace
import unittest
from jam_fuzzer_guest_reference import replay, host_parameters
import current_stf_report_guests_oracle as guests
import current_stf_effects_oracle as effects


class FuzzerGuestReference(unittest.TestCase):
    """Check complete ordered replay, frozen guest evidence and strict refusal of unsupported observations."""

    def test_nonempty_guest_stream(self):
        """Five existing frozen modes cover real report-driven guests and every complete successor map."""
        requests, expected, evidence = replay(guests)
        self.assertEqual(evidence['reference']['guest_executions'], 15)
        self.assertEqual(evidence['reference']['transitions'], 35)
        self.assertEqual(sum(line.startswith('C ') for line in requests), 5)
        self.assertEqual(sum(line.startswith('B ') for line in requests), 35)
        self.assertEqual(sum(line.startswith('O ') for line in expected), 35)
        self.assertEqual([line[2:] for line in requests if line.startswith('C ')],
                         [line[2:] for line in expected if line.startswith('P ')])

    def test_nonempty_storage_preimage_stream(self):
        """The explicit observation-only reference retains all20 guest executions and five nonempty extrinsics."""
        requests, expected, evidence = replay(effects, input_requests=False)
        self.assertEqual(evidence['reference']['guest_executions'], 20)
        self.assertEqual(evidence['reference']['nonempty_extrinsics'], 5)
        self.assertEqual(sum(line.startswith('B ') for line in requests), 10)
        self.assertEqual(sum(line.startswith('O ') for line in expected), 10)

    def test_explicit_host_profiles(self):
        """The4096-byte eligible-code profile and512-byte oversized-code control remain distinct host inputs."""
        profiles = [host_parameters(code_limit=size) for size in (4096, 512)]
        source = SimpleNamespace(expected_observations=lambda: ([], ['P aa', 'B bb', 'O cc', 'P dd', 'B ee', 'O ff'], {}))
        requests, _, _ = replay(source, profiles=profiles)
        self.assertEqual(requests[0], 'C aa '+profiles[0].hex())
        self.assertEqual(requests[2], 'C dd '+profiles[1].hex())
        self.assertEqual(int.from_bytes(profiles[0][98:102], 'little'), 4096)
        self.assertEqual(int.from_bytes(profiles[1][98:102], 'little'), 512)
        for invalid in ([], profiles[:1], [bytes(121)]*2):
            with self.assertRaises(AssertionError): replay(source, profiles=invalid)

    def test_unfinished_fork_is_refused(self):
        """A sibling cannot become a continuation or cross a reset without its original-last child."""
        for lines in (['P aa', 'V bb', 'O cc'],
                      ['P aa', 'V bb', 'O cc', 'V dd', 'O ee'],
                      ['P aa', 'V bb', 'O cc', 'P dd', 'B ee', 'O ff']):
            source = SimpleNamespace(expected_observations=lambda rows=lines: ([], rows, {}))
            with self.assertRaises(AssertionError):
                replay(source, forks=True)
        source = SimpleNamespace(expected_observations=lambda: ([], ['P aa', 'V bb', 'O cc', 'B dd', 'O ee'], {}))
        with self.assertRaises(AssertionError):
            replay(source)

    def test_partial_or_substituted_stream_is_refused(self):
        """An incomplete or disconnected map cannot silently become a successful replay request."""
        for lines in ([], ['P aa'], ['B aa', 'O bb'], ['P aa', 'B bb'], ['P aa', 'N ignored'], ['P aa', 'O bb']):
            source = SimpleNamespace(expected_observations=lambda rows=lines: ([], rows, {}))
            with self.assertRaises(AssertionError):
                replay(source)
