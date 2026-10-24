# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Require actual successful journal work and a native call graph before accepting sampled consumers."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import storage_light_reconstruction_profile as profile
from test_storage_light_journal_benchmark import witness


class ReconstructionAdmission(unittest.TestCase):
    """Sampling success cannot override child failure, changed bytes or altered deterministic work."""

    def test_completed_consumers(self):
        for size in (64, 1024):
            _, raw, _ = witness(size, 'journal')
            self.assertEqual(profile.admit(raw, size, 0, 'a'*64, 'a'*64, 'Call graph:\n edit'),
                             profile.paired.parse(raw, size, 'journal'))

    def test_refusals(self):
        _, raw, _ = witness(64, 'journal')
        for code, digest, sample in [(1, 'a'*64, 'Call graph:'), (False, 'a'*64, 'Call graph:'),
                                    (0, 'b'*64, 'Call graph:'), (0, 'a'*64, ''), (0, 'a'*64, 'failed')]:
            with self.assertRaises(ValueError):
                profile.admit(raw, 64, code, digest, 'a'*64, sample)
        with self.assertRaises(ValueError):
            profile.admit(raw.replace('\t176\t', '\t175\t'), 64, 0, 'a'*64, 'a'*64, 'Call graph:')


if __name__ == '__main__':
    unittest.main()
