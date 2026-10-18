# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal optional assignment composition and independent guarantee/registration time checks."""
import unittest
from state_availability_oracle import wire,encode,decode,record,frame_wire,MAX


# Byte expectations here are independent of native guarantee or assignment encoders.
class AvailabilityHarness(unittest.TestCase):
    # All absent slots have one byte apiece, with no outer sequence count.
    def test_absent(self):
        self.assertEqual(wire([None,None]),b'\0\0')
        self.assertEqual(decode(b'\0\0extra',(2,6,MAX,0,2)),'2 2 0 0 0')

    # Full guarantee includes report, its own E4 slot and credentials before the separate E4 registration time.
    def test_layout(self):
        g=record(0);g['slot']=0x01020304
        value=dict(guarantee=g,registered=0x04030201)
        body=frame_wire([g])[1:]
        self.assertEqual(wire([value,None]),b'\1'+body+b'\1\2\3\4\0')
        self.assertTrue(decode(wire([value,None]),(2,6,MAX,2,MAX)).endswith(' 0'))

    # Absent and present registration zero remain distinguishable, and parent byte ceilings include tags/timestamps.
    def test_limits(self):
        value=dict(guarantee=record(0),registered=0);rows=[value,None];n=len(wire(rows))
        self.assertTrue(encode(rows,(2,6,MAX,1,n)).endswith(wire(rows).hex()))
        self.assertEqual(encode(rows,(2,6,MAX,0,n)),'limitexceeded')
        self.assertEqual(decode(wire(rows),(2,6,MAX,1,n-1)),'limitexceeded')

    # Profile configuration and fixed source length are separate from report byte syntax.
    def test_shape(self):
        self.assertEqual(encode([None],(2,6,MAX,2,MAX)),'invalidcount')
        self.assertEqual(decode(b'',(1,6,MAX,2,MAX)),'invalidconfig')
        self.assertEqual(decode(b'',(2,6,MAX,2,1)),'limitexceeded')

    # Unknown optional tags and missing registration bytes reject the entire component.
    def test_malformed(self):
        self.assertEqual(decode(b'\2',(2,6,MAX,2,MAX)),'invalidtag')
        self.assertEqual(decode(b'\0',(2,6,MAX,2,MAX)),'truncated')
        raw=wire([dict(guarantee=record(0),registered=0),None])
        self.assertEqual(decode(raw[:-2],(2,6,MAX,2,MAX)),'truncated')

    # Zero/one credentials are not valid guarantees even inside state; source wrappers do not weaken the child rule.
    def test_credentials(self):
        value=dict(guarantee=record(0,1),registered=0)
        self.assertEqual(encode([value,None],(2,6,MAX,2,MAX)),'invalidcredential')
        self.assertEqual(decode(wire([value,None]),(2,6,MAX,2,MAX)),'invalidcredential')


# Importing literal expectations never executes upstream generators or invokes compilers.
if __name__=='__main__':
    unittest.main(verbosity=2)
