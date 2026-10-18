# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Regression checks for the independent live RPC harness's WebSocket length handling.

Provides unittest discovery cases for valid medium frames and rejected 64-bit length prefixes.
"""
import io
import struct
import unittest
from rpc_checks import receive


# The in-memory receive-only socket supplies deterministic independent wire bytes.
class Wire:
    # Retain only this test's immutable frame bytes.
    def __init__(self, data):
        self.data = io.BytesIO(data)

    # Match the socket read contract used by the exact-length helper.
    def recv(self, count):
        return self.data.read(count)


# Decode the boundary payload that first appeared in the genesis parent-unavailable response.
class RpcFrameLengths(unittest.TestCase):
    # 127 is a valid decoded medium length, distinct from the 64-bit length discriminator.
    def test_medium_lengths(self):
        for size in (126, 127, 128, 65535):
            # Construct framing independently of the harness's client send helper.
            with self.subTest(size=size):
                payload = b'x' * size
                self.assertEqual(receive(Wire(b'\x81\x7e' + struct.pack('!H', size) + payload)), (1, payload))

    # The bounded endpoint never emits a 64-bit length; reject its marker before reading payload.
    def test_large_length_marker(self):
        with self.assertRaises(AssertionError):
            receive(Wire(b'\x81\x7f'))
