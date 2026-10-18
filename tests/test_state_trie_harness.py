# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal topology and boundary checks protect the independent trie reference itself."""
import unittest
from state_trie_oracle import tree,reference,MAX
from state_layout_oracle import digest,leaf,branch


# Expected topology here is constructed explicitly, without the oracle's recursive partition helper.
class StateTrieHarness(unittest.TestCase):
    # Empty dictionaries have zero roots even with zero resource ceilings.
    def test_empty(self):
        self.assertEqual(tree([]),(bytes(32),0))
        self.assertEqual(reference([],(0,0,0,0)),bytes(32).hex()+' 0 0')

    # A singleton stops at its leaf rather than adding 248 prefix branches.
    def test_singleton(self):
        key=bytes(31);value=b'abc'
        self.assertEqual(tree([(key,value)]),(digest(leaf(key,value)),1))

    # A divergence in the first bit gives exactly one branch and two leaf children.
    def test_first_bit(self):
        a=bytes(31);b=b'\x80'+bytes(30)
        expected=digest(branch(digest(leaf(a,b'')),digest(leaf(b,b'x'))))
        self.assertEqual(tree([(b,b'x'),(a,b'')]),(expected,3))

    # A final-bit divergence preserves all 247 preceding unary branches, including zero empty siblings.
    def test_last_bit(self):
        a=bytes(31);b=bytes(30)+b'\1'
        root=digest(branch(digest(leaf(a,b'')),digest(leaf(b,b''))))
        # Explicitly wrap the final split with each common zero-bit branch.
        for _ in range(247):
            root=digest(branch(root,bytes(32)))
        self.assertEqual(tree([(a,b''),(b,b'')]),(root,250))
        self.assertEqual(reference([(a,b''),(b,b'')],(2,0,0,249)),'limitexceeded')

    # Duplicate identities are invalid with equal or unequal values, regardless of input order.
    def test_duplicates(self):
        self.assertEqual(reference([(bytes(31),b'')]*2,(MAX,)*4),'duplicatekey')
        self.assertEqual(reference([(bytes(31),b'a'),(bytes(31),b'b')],(MAX,)*4),'duplicatekey')

    # Exact byte ceilings accept values while one byte below rejects each independent payload budget.
    def test_payload_limits(self):
        entries=[(bytes(31),bytes(33))]
        self.assertTrue(reference(entries,(1,33,33,1)).endswith(' 1 1'))
        self.assertEqual(reference(entries,(1,32,33,1)),'limitexceeded')
        self.assertEqual(reference(entries,(1,33,32,1)),'limitexceeded')


# Importing literal expectations has no compiler or native-library side effects.
if __name__=='__main__':
    unittest.main(verbosity=2)
