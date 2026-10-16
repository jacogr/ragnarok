"""Literal domain/raw-value/capture anchors independent of native code."""
import unittest
from state_service_values_oracle import key,encode,capture,MAX


# Explicit expected state keys anchor domain prefixes and distinguish raw values from framed blobs.
class ServiceValuesHarness(unittest.TestCase):
    # Empty storage keys still hash their E4 storage namespace marker.
    def test_storage_domain(self):
        self.assertEqual(key('S',0,b'').hex(),'00c700b000d1003d60856218bc53f8a730be41f3e0ca895ca65b8500a73ea1')
        self.assertEqual(encode('S',0,b'',b'',(0,0)).split()[-1],'-')

    # Preimage hashes use the distinct E4 marker and have a fixed logical key width of 32 bytes.
    def test_preimage_domain(self):
        self.assertEqual(key('P',0,bytes(32)).hex(),'0004001d00c5003d2ee85f79cf32bf11fa15bbac7cebf6c9d830191fc76175')
        self.assertNotEqual(key('S',0,bytes(32)),key('P',0,bytes(32)))

    # Exact raw values are copied without a natural count, even if their first bytes resemble malformed framing.
    def test_raw(self):
        self.assertEqual(encode('S',1,b'key',b'\x80\0suffix',(3,8)).split()[-1],b'\x80\0suffix'.hex())
        self.assertEqual(encode('P',1,bytes(32),b'not its preimage',(32,MAX)).split()[-1],b'not its preimage'.hex())

    # Logical key limits exclude fixed namespace overhead; value limits independently bound raw bytes.
    def test_policy(self):
        self.assertEqual(encode('P',0,bytes(32),b'',(31,MAX)),'limitexceeded')
        self.assertEqual(encode('S',0,b'key',b'v',(2,MAX)),'limitexceeded')
        self.assertEqual(encode('S',0,b'',b'v',(0,0)),'limitexceeded')

    # Capture checks interleaved service bytes but cannot reverse or classify the supplied hashed identity.
    def test_capture_binding(self):
        state_key=key('S',0x01020304,b'key')
        self.assertEqual(capture(0,state_key,b'v',1),'invalidservicekey')
        changed=bytearray(state_key);changed[1]^=255
        self.assertTrue(capture(0x01020304,bytes(changed),b'v',1).endswith(' 1 76'))
        self.assertEqual(capture(0,state_key,b'v',0),'limitexceeded')

    # A raw value's external extent is authoritative; a suffix is more value bytes rather than unconsumed framing.
    def test_capture_extent(self):
        state_key=key('S',0,b'')
        self.assertTrue(capture(0,state_key,b'',0).endswith(' 0 0 -'))
        self.assertTrue(capture(0,state_key,b'vextra',6).endswith(' 0 6 766578747261'))


# Importing the harness never builds native code or executes upstream scripts.
if __name__=='__main__':
    unittest.main()
