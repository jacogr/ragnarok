"""Literal independent-oracle anchors; production code is not imported here."""
import unittest
from quic_protocol_oracle import name, frame


# Anchors protect byte order, boundary/FIN semantics and the exact radix-32 alphabet.
class ProtocolOracleTests(unittest.TestCase):
    def test_names(self):
        self.assertEqual(name(bytes(32)), '$e'+'$'*52)
        self.assertEqual(name((1).to_bytes(32,'little')), '$ea'+'$'*51)
        self.assertEqual(name((32).to_bytes(32,'little')), '$e$a'+'$'*50)
        self.assertEqual(name((2**256-1).to_bytes(32,'little')), '$e'+'6'*51+'a')

    def test_frames(self):
        self.assertEqual(frame(bytes.fromhex('8f00000000'),True,32,True),'ok 0 5')
        self.assertEqual(frame(bytes.fromhex('03000000010203'),False,1024,True),'ok 3 7')
        self.assertEqual(frame(bytes.fromhex('03000000010203'),False,1024,False),'2')
        self.assertEqual(frame(bytes.fromhex('030000000102'),False,1024,True),'4')
        self.assertEqual(frame(bytes.fromhex('0300000001020304'),False,1024,True),'7')
        self.assertEqual(frame(bytes.fromhex('9000000000'),True,32,False),'5')
        self.assertEqual(frame(bytes.fromhex('ffffffff'),False,1024,False),'6')
        self.assertEqual(frame(b'',False,-1,False),'3')


# Importing these tests performs no native build, fixture generation or network operation.
if __name__ == '__main__':
    unittest.main(verbosity=2)
