# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Frozen independent service proof namespaces and current metadata remain deliberate evidence."""
import hashlib
from pathlib import Path
import unittest
from state_service_reference import fixture, hashed


class StateServiceReferenceTests(unittest.TestCase):
    """Freeze the complete independent byte model and explicit namespace literals."""
    def test_frozen(self):
        # Corpus changes require an intentional fixture pin update, never runtime regeneration.
        self.assertEqual(Path(__file__).with_name('fixtures').joinpath('state-service-proofs.txt').read_text(), fixture())

    def test_empty_storage_literal(self):
        # Interleave one explicit service's bytes with hashlib's independently computed raw domain.
        digest = hashlib.blake2b(b'\xff'*4, digest_size=32).digest()
        expected = bytes([0x78, digest[0], 0x56, digest[1], 0x34, digest[2], 0x12, digest[3]]) + digest[4:27]
        self.assertEqual(hashed(0x12345678, b'\xff'*4), expected)
