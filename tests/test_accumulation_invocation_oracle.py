# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal seed and compact-width witnesses for the independent accumulation bootstrap oracle."""
import hashlib
import unittest
from accumulation_invocation_fixtures import candidate, FIRST, END


# Small literal seeds distinguish compact general encoding from accidental E4 header encodings.
class AccumulationInvocationOracleTests(unittest.TestCase):
    # Both scalar terms occupy one octet for the literal zero/one witness.
    def test_seed(self):
        expected = int.from_bytes(hashlib.blake2b(b'\x01'+bytes(32)+b'\x00', digest_size=32).digest()[:4], 'little') % (END-FIRST)+FIRST
        self.assertEqual(candidate(1, bytes(32), 0), expected)

    # Crossing a compact boundary changes exact seed bytes without padding, framing or a terminator.
    def test_boundary(self):
        expected = int.from_bytes(hashlib.blake2b(b'\x80\x80'+bytes([7])*32+b'\x7f', digest_size=32).digest()[:4], 'little') % (END-FIRST)+FIRST
        self.assertEqual(candidate(128, bytes([7])*32, 127), expected)
