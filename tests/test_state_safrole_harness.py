# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal framing, cardinality and resource checks for the independent state reference."""
import unittest
from state_safrole_oracle import extent,decode,MAX
from state_layout_oracle import chapter_key
from test_codec import reference_encode as natural


# Expectations are literal protocol boundaries, independent of native encoder/decoder behavior.
class StateSafroleHarness(unittest.TestCase):
    # Each covered top-level chapter has its exact namespace octet and thirty zeroes.
    def test_keys(self):
        for chapter in (6,7,8,9,11):
            self.assertEqual(chapter_key(chapter),bytes([chapter])+bytes(30)) # No service-index interleaving occurs here.

    # Allowed validator populations are multiples of three, from six through three times core count.
    def test_population(self):
        self.assertEqual(extent(6,1,(2,6,2017)),2017)
        self.assertEqual(extent(9,1,(2,MAX,MAX)),'invalidcount')
        self.assertEqual(extent(7,1,(341,MAX,MAX)),'invalidcount')
        self.assertEqual(extent(0,1,(341,MAX,MAX)),'invalidcount')
        self.assertEqual(extent(1023,2,(341,1023,MAX)),343730)

    # Invalid configuration precedes input parsing and cannot silently fall back to a profile.
    def test_config(self):
        self.assertEqual(decode(b'',(1,MAX,MAX)),'invalidconfig')
        self.assertEqual(extent(6,1,(0,MAX,MAX)),'invalidconfig')

    # Exact byte policy includes count framing, not merely the 336-byte records.
    def test_limits(self):
        self.assertEqual(extent(6,1,(2,5,MAX)),'limitexceeded')
        self.assertEqual(extent(6,1,(2,6,2016)),'limitexceeded')
        self.assertEqual(extent(MAX,9,(MAX,MAX,MAX)),'lengthoverflow')

    # Count framing is canonical, and absent final record bytes cannot be padded into a success.
    def test_framing(self):
        self.assertEqual(decode(b'\x80\x06',(2,6,MAX)),'noncanonical')
        self.assertEqual(decode(b'\x06'+bytes(2015),(2,6,MAX)),'truncated')
        self.assertEqual(natural(129),b'\x80\x81')

    # A valid prefix consumes exactly its own payload while preserving opaque source bytes/order.
    def test_suffix(self):
        source=bytes(range(256))*7+bytes(224)
        self.assertEqual(len(source),2016)
        self.assertEqual(decode(b'\x06'+source+b'extra',(2,6,2017)),'2017 6 '+source.hex())


# Literal checks never compile code or alter upstream fixtures.
if __name__=='__main__':
    unittest.main(verbosity=2)
