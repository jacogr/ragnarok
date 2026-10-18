# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal witnesses for accounts code-envelope parsing and the separate Psi_A code-size gate."""
import unittest
from accumulation_service_fixtures import resolve


# Independent small examples anchor the envelope oracle without native decoding.
class AccumulationServiceOracleTests(unittest.TestCase):
    # Metadata has the only length prefix; the remaining suffix is code, including a valid empty suffix.
    def test_envelope(self):
        self.assertEqual(resolve(b'\x01\xff\x02\x03', 2, 4), ('Ready', b'\x02\x03'))
        self.assertEqual(resolve(b'\x01\xff', 0, 2), ('Ready', b''))
        self.assertEqual(resolve(b'\x01\xff\x02', 0, 3), ('Oversized', b'\x02'))

    # Malformed framing is unavailable code; resource refusal has a distinct reason.
    def test_refusals(self):
        self.assertEqual(resolve(b'\x02\xff', 10, 2), ('Malformed', b''))
        self.assertEqual(resolve(b'\x80\x00', 10, 2), ('Malformed', b''))
        self.assertEqual(resolve(b'\x00', 0, 0), ('LimitExceeded', b''))
