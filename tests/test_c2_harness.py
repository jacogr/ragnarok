"""Literal independent wire/field checks protect the C.2 reference equations."""
import unittest
from c2_oracle import BROAD,MAX,example,wire,decode,encode


# Distinct gas/tag/memo encodings and resource precedence are explicit known answers, not native round trips.
class C2Harness(unittest.TestCase):
    # Availability is exactly the six-field 104-byte prefix of a complete report, without its context.
    def test_availability(self):
        value=example('A');data=wire('A',value)
        self.assertEqual(len(data),104)
        self.assertEqual(data[32:36],bytes([255])*4)
        self.assertEqual(data[68:70],b'\xff\x03')
        self.assertEqual(data[102:104],b'\xff\xff')
        self.assertTrue(decode('A',data+b'context').startswith('104 '))

    # Transfers include tag one, two E4 services, E8 balance, exactly 128 memo bytes and E8 gas.
    def test_transfer(self):
        value=example('T',gas=128);data=wire('T',value)
        self.assertEqual(len(data),153)
        self.assertEqual(data[0],1)
        self.assertEqual(data[17:145],bytes(range(128)))
        self.assertEqual(data[145:],b'\x80'+bytes(7))
        self.assertTrue(decode('I',data).startswith('1 153 '))

    # Operand gas 128 is a two-octet natural; it must not inherit the transfer/work-digest E8 encoding.
    def test_operand_gas_and_tag(self):
        value=example('O',gas=128,payload=b'',trace=b'');data=wire('O',value)
        self.assertEqual(data[129:],b'\x80\x80\0\0\0')
        self.assertEqual(len(data),134)
        self.assertEqual(encode('UO',value,BROAD,len(data)),data.hex())
        self.assertTrue(decode('I',data).startswith('0 134 '))

    # Payload-free work errors remove exactly the success blob length/payload, preserving the final trace count.
    def test_work_alternatives(self):
        self.assertEqual(wire('O',example('O',gas=0,tag=0,payload=b'',trace=b''))[129:],b'\0\0\0\0')
        # All six error alternatives keep their exact existing work-result tag, with no success length.
        for tag in range(1,7):
            self.assertEqual(wire('O',example('O',gas=0,tag=tag,trace=b''))[129:],bytes([0,tag,0]))
        self.assertEqual(decode('O',bytes([0])+bytes(128)+b'\0\7'),'invalidtag')

    # A fixed memo never gains a byte-string count, including when its first byte resembles a natural prefix.
    def test_memo_identity(self):
        value=list(example('T',gas=MAX));value[3]=bytes([255])*128;data=wire('T',tuple(value))
        self.assertEqual(data[17:145],bytes([255])*128)
        self.assertEqual(len(data),153)
        self.assertTrue(decode('T',data).startswith('153 '))

    # Invalid configuration and canonical scalar framing precede later domain/resource decisions.
    def test_precedence(self):
        self.assertEqual(decode('A',b'',(0,0,0,0,0)),'invalidconfig')
        self.assertEqual(decode('T',b'\x80\1'),'noncanonical')
        self.assertEqual(decode('O',b'\1'),'invalidtag')
        self.assertEqual(decode('T',b'\1',BROAD[:-1]+(0,)),'truncated')
        self.assertEqual(decode('O',b'\0'+bytes(128),BROAD[:-1]+(0,)),'limitexceeded')

    # Final authorization trace and aggregate payload limits are enforced before any output capacity decision.
    def test_payload_budgets(self):
        value=example('O',payload=b'abc',trace=b'de');data=wire('O',value)
        cfg=(341,3,2,4,MAX)
        self.assertEqual(decode('O',data,cfg),'limitexceeded')
        self.assertEqual(encode('O',value,cfg,0),'limitexceeded')
        self.assertEqual(encode('UT',example('T'),(341,0,0,0,153),153),wire('T',example('T')).hex())

    # Missing final fields and hostile length claims cannot return earlier metadata or a partially owned record.
    def test_late_and_huge(self):
        base=wire('O',example('O',gas=0,tag=1,trace=b''))[:-1]
        self.assertEqual(decode('O',base),'truncated')
        self.assertEqual(decode('O',base+b'\xff'+bytes([255])*8),'truncated')
        self.assertEqual(decode('O',base+b'\xff'+bytes([255])*8,(341,0,0,0,MAX)),'limitexceeded')


# Loading reference functions never builds native binaries or changes upstream sources.
if __name__=='__main__':
    unittest.main(verbosity=2)
