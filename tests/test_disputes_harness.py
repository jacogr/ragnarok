"""Known-answer checks for the test-only disputes oracle and its published fixture distinction."""
import copy
import unittest
from disputes_oracle import example,wire,fields,encode,decode,published


# Literal offsets and small known answers guard the independent test harness against mirrored mistakes.
class DisputesHarness(unittest.TestCase):
    # All three empty sequence counts are present, with unrelated suffix bytes left unconsumed.
    def test_empty(self):
        value=example(0,0,0,0)
        self.assertEqual(wire(value),b'\0\0\0')
        self.assertEqual(encode(value,6,3,3),'000000')
        self.assertEqual(decode(b'\0\0\0\xff',6,3),'3 0 0 0')

    # Literal E4/E2 and Boolean offsets differ from general-natural counts.
    def test_offsets(self):
        value=example(1,1,0,1);value['verdicts'][0]['votes'][0]['index']=258
        value['verdicts'][0]['votes'][0]['vote']=True
        data=wire(value)
        self.assertEqual(data[:1],b'\1')
        self.assertEqual(data[33:38],bytes.fromhex('ffffffff01'))
        self.assertEqual(data[38:41],bytes.fromhex('010201'))
        self.assertEqual(data[105:107],b'\0\1')
        self.assertEqual(data[139],0)
        self.assertEqual(decode(data,1023,len(data)),str(len(data))+' '+fields(value))

    # Votes are variable in 0.8.0; exact context-dependent quorum is not a framing condition.
    def test_variable_votes(self):
        value=example(1,128,0,0);data=wire(value)
        self.assertEqual(data[37:39],bytes.fromhex('8080'))
        self.assertEqual(decode(data,1023,len(data)),str(len(data))+' '+fields(value))
        self.assertEqual(encode(example(1,0,0,0),6,40,40),wire(example(1,0,0,0)).hex())

    # Both published profiles reconstruct byte-for-byte but violate verdict report-hash ordering.
    def test_published_order(self):
        # Both exact release profiles retain the same deliberate ordering rejection.
        for profile in ('tiny','full'):
            value=published(profile);data=wire(value)
            self.assertEqual(decode(data,1023,len(data)),'noncanonical')
            canonical=copy.deepcopy(value);canonical['verdicts'].sort(key=lambda v:v['target'])
            self.assertEqual(decode(wire(canonical),1023,len(data)),str(len(data))+' '+fields(canonical))

    # Ordering by offender key must not accidentally become ordering by report target or cross-section key.
    def test_offender_order(self):
        value=example(0,0,2,2);data=wire(value)
        self.assertEqual(decode(data,6,len(data)),str(len(data))+' '+fields(value))
        value['faults'].reverse()
        self.assertEqual(decode(wire(value),6,len(data)),'noncanonical')

    # Invalid tags, noncanonical naturals and huge counts retain distinct failure reasons.
    def test_malformed(self):
        self.assertEqual(decode(b'\x80\0',6,100),'noncanonical')
        self.assertEqual(decode(b'\x11',6,100),'limitexceeded')
        data=bytearray(wire(example(1,1,0,0)));data[38]=2
        self.assertEqual(decode(bytes(data),6,1000),'invalidtag')
        self.assertEqual(decode(bytes(data),0,1000),'invalidconfig')


# Harness checks remain separate from native compilation and decoder workload counts.
if __name__=='__main__':
    unittest.main(verbosity=2)
