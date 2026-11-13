# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal witnesses for accounts code-envelope parsing and the separate Psi_A code-size gate."""
import unittest
from accumulation_service_fixtures import resolve


# Independent small examples anchor the envelope oracle without native decoding.
class AccumulationServiceOracleTests(unittest.TestCase):
    def test_envelope(self):
        self.assertEqual(resolve(b'\x01\xff\x02\x03', 4, 4), ('Ready', b'\x01\xff\x02\x03'))
        self.assertEqual(resolve(b'\x01\xff\x02\x03', 3, 4), ('Oversized', b'\x01\xff\x02\x03'))

    def test_refusals(self):
        self.assertEqual(resolve(b'\x02\xff', 10, 2), ('Ready', b'\x02\xff'))
        self.assertEqual(resolve(b'\x80\x00', 10, 2), ('Ready', b'\x80\x00'))
        self.assertEqual(resolve(b'\x00', 1, 0), ('LimitExceeded', b''))
        self.assertEqual(resolve(b'\x00', 0, 0), ('Oversized', b'\x00'))
