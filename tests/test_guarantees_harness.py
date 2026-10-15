"""Independent guarantee oracle examples guard wrapper framing and failure precedence."""
import copy
import unittest
from guarantees_oracle import record,wire,decode,encode,published


# Concrete examples verify the mathematical test oracle before native agreement can conceal a shared mistake.
class GuaranteeOracleTests(unittest.TestCase):
    # Slot and credential identities use fixed little-endian E4/E2 rather than general naturals.
    def test_fixed_fields(self):
        value=record(0);value['slot']=0x01020304
        data=wire([value]);at=1+len(value['report'])
        self.assertEqual(data[at:at+7],bytes.fromhex('04030201020000'))
        self.assertTrue(decode(data,341,1023,len(data)).startswith(f'1 {len(data)} '))
    # A late duplicate identity outranks destination capacity and cannot authorize an earlier write.
    def test_late_failure(self):
        values=[record(0),record(1)];values[-1]['credentials']=[(0,bytes(64)),(0,bytes(64))]
        self.assertEqual(encode(values,341,1023,1048576,0),'noncanonical')
        self.assertEqual(decode(wire(values),341,1023,1048576),'noncanonical')
    # Both published profiles retain exact source/binary identities, even when tiny's sample is not chain-eligible.
    def test_published(self):
        for chain in ('tiny','full'):
            values=published(chain);data=wire(values)
            self.assertTrue(decode(data,341,1023,len(data)).startswith('1 '))
        self.assertEqual(decode(wire(published('tiny')),2,6,1048576),'limitexceeded')
    # Empty frames still need a canonical count, valid caller configuration and one byte of budget.
    def test_empty_bounds(self):
        self.assertEqual(decode(b'\0',341,1023,1),'0 1 0')
        self.assertEqual(decode(b'\0',341,1023,0),'limitexceeded')
        self.assertEqual(decode(b'\0',1,6,1),'invalidconfig')


# Direct execution checks test infrastructure without building production binaries.
if __name__=='__main__':
    unittest.main()
