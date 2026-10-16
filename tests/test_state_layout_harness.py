"""Literal known answers for current 31-byte state keys, MSB trie flags and independent Blake2b node commitments."""
import unittest
from state_layout_oracle import chapter_key,chapter_service,service_key,branch,leaf,decode,hash_node,embedded_source,digest


# These expectations target the pinned equations, not native encode/decode round trips.
class StateLayoutHarness(unittest.TestCase):
    # State chapters and service indices have exact 31-byte key positions and E4 little-endian interleaving.
    def test_chapters(self):
        self.assertEqual(chapter_key(255),b'\xff'+bytes(30))
        self.assertEqual(chapter_service(255,0x01020304),bytes([255,4,0,3,0,2,0,1,0])+bytes(22))

    # C(s,h) keeps digest octets 0..26 around exactly four service bytes; it never prefixes h with its length.
    def test_hashed_key(self):
        hashed=digest(b'abc');key=service_key(0x01020304,b'abc')
        self.assertEqual(key[:8],bytes([4,hashed[0],3,hashed[1],2,hashed[2],1,hashed[3]]))
        self.assertEqual(key[8:],hashed[4:27])
        self.assertEqual(len(key),31)

    # The branch loses exactly one left hash bit; high right bits and every other left bit remain unchanged.
    def test_partial_branch(self):
        right=bytes([255])*32
        self.assertEqual(branch(bytes([128])+bytes(31),right),bytes(32)+right)
        self.assertEqual(branch(bytes([127])+bytes(31),right),bytes([127])+bytes(31)+right)
        self.assertEqual(branch(bytes([128])+bytes(31),right),branch(bytes(32),right))

    # Inline empty/32-byte values and 33-byte hashed values have exact distinct wire headers.
    def test_leaf_threshold(self):
        key=bytes(range(31))
        self.assertEqual(leaf(key,b''),b'\x80'+key+bytes(32))
        self.assertEqual(leaf(key,bytes(32)),b'\xa0'+key+bytes(32))
        self.assertEqual(leaf(key,bytes(33)),b'\xc0'+key+digest(bytes(33)))
        self.assertEqual(len(leaf(key,bytes(33))),64)

    # Canonical inline padding and reserved regular-leaf flags are validated before hashing raw nominal nodes.
    def test_canonicality(self):
        self.assertEqual(decode(b'\xa1'+bytes(63)),'noncanonical')
        self.assertEqual(decode(b'\xc1'+bytes(63)),'noncanonical')
        self.assertEqual(decode(b'\x80'+bytes(62)+b'\1'),'noncanonical')
        self.assertEqual(hash_node(b'\x80'+bytes(62)+b'\1'),'noncanonical')
        self.assertEqual(embedded_source(bytes(31),33,bytes(32)),'noncanonical')

    # The current node formula uses raw Blake2b-256 of 64 bytes, with no general-tree $node domain prefix.
    def test_hash_and_prefix(self):
        node=leaf(bytes(31),b'')
        self.assertEqual(hash_node(node),digest(node).hex())
        self.assertNotEqual(digest(node),digest(b'$node'+node))
        self.assertTrue(decode(node+b'extra').startswith('64 E '))
        self.assertEqual(decode(node[:-1]),'truncated')


# Loading these equations never modifies source pins or executes an upstream generator.
if __name__=='__main__':
    unittest.main(verbosity=2)
