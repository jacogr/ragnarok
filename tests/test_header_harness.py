"""Known-answer source/offset checks protect the independent header oracle from mirrored mistakes."""
import copy
import unittest
from header_oracle import TINY,FULL,example,published,wire,fields,decode,encode


# These literal layout and policy checks do not compile or call the native implementation.
class HeaderHarness(unittest.TestCase):
    # No-marker headers retain E4 slot, two tag octets, E2 author, entropy proof, offenders then final seal.
    def test_unsigned_prefix(self):
        value=example('H');data=wire('H',value);unsigned=wire('U',value)
        self.assertEqual(data[:-96],unsigned)
        self.assertEqual(data[96:100],b'\xff'*4)
        self.assertEqual(data[100:104],bytes.fromhex('00000500'))
        self.assertEqual(data[104:200],bytes([4])*96)
        self.assertEqual(data[200],3)
        self.assertEqual(data[-96:],bytes([11])*96)
        self.assertEqual(decode('U',data,TINY),f'{len(unsigned)} '+fields('U',value))

    # Variable 0.8.0 validator count follows two fixed entropy hashes, not an old fixed-population layout.
    def test_epoch_count(self):
        value=example('E');data=wire('E',value)
        self.assertEqual(len(data),450)
        self.assertEqual(data[:1],b'\1');self.assertEqual(data[65],6)
        self.assertEqual(data[66:98],bytes(32));self.assertEqual(data[98:130],bytes([10])*32)
        self.assertEqual(decode('E',b'\0x',TINY),'1 0')

    # Winner marker has one optional tag and exactly epochSlots fixed 33-byte tickets with no count.
    def test_fixed_winners(self):
        value=example('W');data=wire('W',value)
        self.assertEqual(len(data),397)
        self.assertEqual(data[:34],b'\1'+bytes(33))
        self.assertEqual(data[34:66],bytes([1])*32)
        self.assertEqual(data[66],17)
        self.assertEqual(decode('W',data+b'x',TINY),f'{len(data)} '+fields('W',value))

    # Full E1 attempts retain one byte at all compact-natural boundaries.
    def test_attempts(self):
        for attempt in (0,127,128,255):
            # Ticket id width never changes when attempt's high bit is set.
            value=example('T');value['attempt']=attempt
            self.assertEqual(len(wire('T',value)),33)
            self.assertEqual(wire('T',value)[32],attempt)

    # Offender markers concatenate separately ordered evidence sections; global sort/dedup would change bytes.
    def test_sequence_policy(self):
        value=example('H');data=wire('H',value)
        self.assertEqual(decode('H',data,TINY),f'{len(data)} '+fields('H',value))
        value['offenders_mark']=[bytes(32)]*32
        self.assertTrue(decode('H',wire('H',value),TINY).startswith(str(len(wire('H',value)))+' '))
        value['offenders_mark'].append(bytes(32))
        self.assertEqual(decode('H',wire('H',value),TINY),'limitexceeded')

    # Pending epoch population may differ from the posterior author's population while sharing core limits.
    def test_independent_populations(self):
        value=example('E');value['validators']*=2
        self.assertEqual(encode('E',value,(4,6,12,10000),10000),wire('E',value).hex())
        self.assertEqual(encode('E',value,TINY,10000),'limitexceeded')
        value['validators']=value['validators'][:7]
        self.assertEqual(decode('E',wire('E',value),FULL),'limitexceeded')

    # Every pinned full header and its seal-free signing payload agree with named JSON sources.
    def test_published(self):
        for profile,config in (('tiny',TINY),('full',FULL)):
            # Both marker choices and both source encodings retain exact release provenance.
            for name in ('header_0','header_1'):
                value=published(profile,name)
                for kind in ('H','U'):
                    data=wire(kind,value)
                    self.assertEqual(decode(kind,data,config),f'{len(data)} '+fields(kind,value))

    # Tag, canonical count and invalid-author failures remain distinct before any default value can appear.
    def test_failures(self):
        self.assertEqual(decode('E',b'\2',TINY),'invalidtag')
        self.assertEqual(decode('W',b'\xff',TINY),'invalidtag')
        self.assertEqual(decode('E',b'\1'+bytes(64)+b'\x80\0',TINY),'noncanonical')
        value=example('H');value['author_index']=6
        self.assertEqual(decode('H',wire('H',value),TINY),'invalidauthor')
        self.assertEqual(decode('W',b'\1',TINY[:2]+(2**64-1,TINY[3])),'truncated')
        self.assertEqual(decode('H',b'',(2,6,0,1000)),'invalidconfig')


# Running this file validates the independent oracle only and never alters upstream fixtures.
if __name__=='__main__':
    unittest.main(verbosity=2)
