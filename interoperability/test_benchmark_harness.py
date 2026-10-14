#!/usr/bin/env python3
"""Reject fabricated results, leaked ownership and mislabelled samples before trusting benchmark evidence."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import benchmark


# Isolate diagnostic output while testing the harness against controlled native result transcripts.
class MeasurementIntegrity(unittest.TestCase):
    # A dummy public input keeps mocked processes independent of compiler/library/network setup.
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.old_raw = benchmark.RAW
        benchmark.RAW = Path(self.directory.name) / 'raw'
        self.addCleanup(setattr, benchmark, 'RAW', self.old_raw)
        path = Path(self.directory.name) / 'input'
        path.write_bytes(b'abc')
        self.case = {'name': 'integrity', 'kind': 'baseline', 'operation': 'control',
                     'path': str(path), 'expected': 17}

    # Batch averages and real operation latencies must remain distinct in the accepted result.
    def test_distinct_sampling_methods(self):
        transcript = 'VERIFY 17\nBATCH 2 20\nBATCH 2 24\nBATCH 2 28\nLATENCY 99\nEND 17 4096\n'
        with patch.object(benchmark.subprocess, 'check_output', return_value=transcript):
            data = benchmark.native(self.case, 'nim', 2, 3, 1, None)
        self.assertEqual(data['batch_ns_per_operation'], [10, 12, 14])
        self.assertEqual(data['single_operation_ns'], [99])

    # A plausible timing cannot rescue a result that disagrees with the independent operation oracle.
    def test_wrong_result_rejected(self):
        with patch.object(benchmark.subprocess, 'check_output', return_value='VERIFY 18\nEND 0 4096\n'):
            with self.assertRaises(AssertionError):
                benchmark.native(self.case, 'odin', 2, 1, 0, None)

    # End-of-loop fingerprints detect an incorrect operation/call count even when preflight looked valid.
    def test_wrong_loop_checksum_rejected(self):
        transcript = 'VERIFY 17\nBATCH 2 20\nEND 17 4096\n'
        with patch.object(benchmark.subprocess, 'check_output', return_value=transcript):
            with self.assertRaises(AssertionError):
                benchmark.native(self.case, 'nim', 2, 1, 0, None)

    # Never mix an earlier partial run with the requested sample count.
    def test_missing_batch_rejected(self):
        transcript = 'VERIFY 17\nBATCH 2 20\nEND 0 4096\n'
        with patch.object(benchmark.subprocess, 'check_output', return_value=transcript):
            with self.assertRaises(AssertionError):
                benchmark.native(self.case, 'odin', 2, 3, 0, None)

    # The supported printable Nim counter is accepted without reaching into private runtime fields.
    def test_private_nim_counter_format(self):
        self.case['operation'] = 'owned-decode'
        transcript = 'VERIFY 17\nALLOC_NIM 128 0 (allocCount: 256, deallocCount: 256)\nEND 0 4096\n'
        with patch.object(benchmark.subprocess, 'check_output', return_value=transcript):
            data = benchmark.native(self.case, 'nim', 128, 1, 0, None, instrumented=True)
        self.assertEqual(data['calls_per_operation'], 2)
        self.assertIsNone(data['requested_bytes_per_operation'])

    # A released owner must account for every reported allocation; timing success alone cannot hide a leak.
    def test_unreleased_allocation_rejected(self):
        self.case['operation'] = 'owned-decode'
        transcript = 'VERIFY 17\nALLOC 128 256 255 0 1000\nEND 0 4096\n'
        with patch.object(benchmark.subprocess, 'check_output', return_value=transcript):
            with self.assertRaises(AssertionError):
                benchmark.native(self.case, 'odin', 128, 1, 0, None, instrumented=True)

    # Borrowed/prepared APIs cannot silently become allocating implementations without the result exposing it.
    def test_hidden_borrowed_allocation_rejected(self):
        transcript = 'VERIFY 17\nALLOC 128 1 1 0 8\nEND 0 4096\n'
        with patch.object(benchmark.subprocess, 'check_output', return_value=transcript):
            with self.assertRaises(AssertionError):
                benchmark.native(self.case, 'odin', 128, 1, 0, None, instrumented=True)

    # Crypto output is independently checked, rather than relying solely on the two native implementations agreeing.
    def test_wrong_crypto_digest_rejected(self):
        self.case['kind'] = 'blake2b'
        digest = hashlib.blake2b(b'abc', digest_size=32).digest()
        self.case['expected'] = 32 ^ digest[0] ^ digest[-1]
        transcript = f'VERIFY {self.case["expected"]}\nHASH {bytes(32).hex()}\nEND 0 4096\n'
        with patch.object(benchmark.subprocess, 'check_output', return_value=transcript):
            with self.assertRaises(AssertionError):
                benchmark.native(self.case, 'nim', 2, 1, 0, None)


# Importing regression helpers creates no processes or files outside each test's temporary directory.
if __name__ == '__main__':
    unittest.main()
