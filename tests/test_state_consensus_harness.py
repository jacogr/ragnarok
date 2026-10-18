# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal chapter-4 offsets, fixed schedule framing and resource checks for the independent reference.

Exposes ConsensusHarness for unittest discovery; test methods exercise the stated contracts.
"""
import unittest
from state_consensus_oracle import wire,encode,decode,MAX


# Direct literal field expectations protect the test oracle independently of native codec output.
class ConsensusHarness(unittest.TestCase):
    # Build a minimal structural source with two fixed schedule slots and no accumulator tickets.
    def source(self,kind=0):
        return (bytes(2016),bytes([3])*144,kind,bytes([9])*(2*(33 if kind==0 else 32)),b'')

    # No count prefixes accompany ring root or fixed schedule; only pending and accumulator are variable.
    def test_offsets(self):
        raw=wire(self.source())
        self.assertEqual(raw[0],6);self.assertEqual(raw[2017:2161],bytes([3])*144)
        self.assertEqual(raw[2161],0);self.assertEqual(raw[2162:2228],bytes([9])*66)
        self.assertEqual(raw[2228:],b'\0')

    # Ticket and fallback modes have exact tags and distinct per-slot widths.
    def test_modes(self):
        self.assertEqual(len(wire(self.source(0))),2229)
        self.assertEqual(len(wire(self.source(1))),2227)
        raw=bytearray(wire(self.source()));raw[2161]=2
        self.assertEqual(decode(bytes(raw),(2,6,2017,2,2,MAX)),'invalidtag')

    # Ticket identifiers precede E1 attempts, including 128/255; ordering is not changed by serialization.
    def test_ticket_order(self):
        source=(*self.source()[:3],bytes([255])*32+b'\x80'+bytes(32)+b'\xff',bytes([17])*32+b'\xff')
        self.assertEqual(wire(source)[2162:2228],source[3])
        self.assertTrue(wire(source).endswith(b'\1'+source[4]))

    # Every complete parent includes a canonical accumulator count; suffixes remain with the caller.
    def test_prefix(self):
        raw=wire(self.source());config=(2,6,2017,2,2,MAX)
        self.assertTrue(decode(raw+b'extra',config).startswith('2229 '))
        self.assertEqual(decode(raw[:-1],config),'truncated')
        self.assertEqual(decode(raw[:-1]+b'\x80\0',config),'noncanonical')

    # Epoch/schedule cardinality and independent roster/parent byte ceilings precede allocation.
    def test_limits(self):
        source=self.source();config=(2,6,2017,2,2,2229)
        self.assertTrue(encode(source,config).startswith('2229 '))
        self.assertEqual(encode(source,(*config[:5],2228)),'limitexceeded')
        self.assertEqual(encode(source,(2,6,2016,2,2,MAX)),'limitexceeded')
        self.assertEqual(encode(source,(2,6,2017,3,3,MAX)),'invalidcount')

    # Zero and physically unrepresentable epochs fail before any source traversal or allocation.
    def test_config(self):
        self.assertEqual(decode(b'',(2,6,2017,0,0,MAX)),'invalidconfig')
        self.assertEqual(decode(b'',(2,6,2017,MAX,MAX,MAX)),'lengthoverflow')


# Importing the harness has no compiler or upstream-generator side effects.
if __name__=='__main__':
    unittest.main(verbosity=2)
