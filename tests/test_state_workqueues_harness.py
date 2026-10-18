# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal fixed-ring framing and inherited child-policy checks independent of native code."""
import unittest
from state_workqueues_oracle import wire,encode,decode,DEFAULT,MAX,record


# Exact literal fields anchor hash-set and ordered-report equations before any native execution.
class WorkQueuesHarness(unittest.TestCase):
    # Empty slots need count bytes without an outer epoch count, for both component schemas.
    def test_empty(self):
        self.assertEqual(wire('Q',[[],[]]),b'\0\0')
        self.assertEqual(wire('A',[b'',b'']),b'\0\0')
        self.assertEqual(decode('Q',b'\0\0suffix',DEFAULT),'2 2 0 0 0 0')
        self.assertEqual(decode('A',b'\0\0suffix',DEFAULT),'2 2 0 0 0:- 0:-')

    # An accumulated set has one natural count and plain 32-byte hashes per fixed slot.
    def test_accumulated(self):
        raw=bytes(32)+bytes(31)+b'\1'
        self.assertEqual(wire('A',[raw,b'']),b'\2'+raw+b'\0')
        self.assertTrue(decode('A',wire('A',[raw,b'']),DEFAULT).startswith('66 2 2 0 2:'))

    # Report bytes are not length-prefixed; each ordered report is followed by its own dependency-set count.
    def test_ready(self):
        report=record(0)['report'];deps=bytes(32)
        self.assertEqual(wire('Q',[[],[(report,deps)]]),b'\0\1'+report+b'\1'+deps)
        self.assertTrue(decode('Q',wire('Q',[[],[(report,deps)]]),DEFAULT).endswith('1:'+deps.hex()))

    # Canonical hash sets reject equality or descending octets, independently of report/slot sequence order.
    def test_set_order(self):
        a=bytes(32);b=b'\1'+bytes(31)
        for raw in (a+a,b+a):
            self.assertEqual(decode('A',b'\2'+raw+b'\0',DEFAULT),'noncanonical')
            self.assertEqual(encode('Q',[[(record(0)['report'],raw)],[]],DEFAULT),'noncanonical')

    # Slot, row and aggregate policies are independent and every count/payload byte is charged.
    def test_limits(self):
        self.assertEqual(decode('A',b'\0\0',(2,2,MAX,MAX,MAX,MAX,MAX,1)),'limitexceeded')
        self.assertEqual(decode('A',b'\1'+bytes(32)+b'\0',(2,2,0,MAX,MAX,MAX,MAX,MAX)),'limitexceeded')
        self.assertEqual(encode('Q',[[]],DEFAULT),'invalidcount')
        self.assertEqual(decode('Q',b'',(0,2,MAX,MAX,MAX,MAX,MAX,MAX)),'invalidconfig')

    # Child report, late count and final dependency bytes retain precise failures without an earlier owner.
    def test_late_failures(self):
        report=record(0)['report']
        self.assertEqual(decode('Q',b'\0\1'+report+b'\1'+bytes(31),DEFAULT),'truncated')
        self.assertEqual(decode('A',b'\0\x80\0',DEFAULT),'noncanonical')
        self.assertEqual(encode('Q',[[],[(b'',b'')]],DEFAULT),'invalidreport')
        self.assertEqual(decode('A',b'\xff'+b'\xff'*8,DEFAULT),'lengthoverflow')


# Importing the harness never builds code or executes upstream programs.
if __name__=='__main__':
    unittest.main()
