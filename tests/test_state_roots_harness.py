# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Literal transport and unresolved state-width gates for complete mapping evidence.

Exposes StateRootsHarness for unittest discovery; test methods exercise the stated contracts.
"""
import unittest
from state_roots_oracle import mapping, requests
from state_trie_oracle import tree


# Hand-authored maps test the harness without substituting production output for expected roots.
class StateRootsHarness(unittest.TestCase):
    # Original pair order, current key widths and present-empty payloads are retained without projection.
    def test_literal_mapping(self):
        key = '01'+'00'*30
        entries, root = mapping(dict(state_root='0x'+'00'*32,
            keyvals=[dict(key='0x'+key, value='0x')]))
        self.assertEqual(entries, [(bytes.fromhex(key), b'')])
        self.assertEqual(root, bytes(32))

    # Historical 32-byte keys and malformed root identities cannot masquerade as current complete maps.
    def test_widths(self):
        # Each malformed key/root domain is rejected separately, without needing native code.
        for key_bytes, root_bytes in ((32, 32), (30, 32), (31, 31)):
            with self.assertRaises(AssertionError):
                mapping(dict(state_root='0x'+'00'*root_bytes,
                    keyvals=[dict(key='0x'+'00'*key_bytes, value='0x')]))

    # Duplicate pairs remain visible to validation rather than disappearing in a Python dictionary.
    def test_duplicate_mapping(self):
        pair = dict(key='0x'+'00'*31, value='0x01')
        with self.assertRaisesRegex(AssertionError, 'duplicate'):
            mapping(dict(state_root='0x'+'00'*32, keyvals=[pair, pair]))

    # A hand-authored nonempty map exercises tight budgets, order independence and commitment sensitivity.
    def test_variants(self):
        entries = [(bytes(31), b'abc'), (b'\x80'+bytes(30), b'x')]
        root, nodes = tree(entries)
        evidence = dict(state_root=root.hex(), value_bytes=4, nodes=nodes)
        lines, expected, records = requests([(entries, evidence)])
        self.assertEqual(len(lines), 11)
        self.assertEqual(expected[:3], [root.hex()+' 2 3']*3)
        self.assertEqual(expected[3:7], ['limitexceeded']*4)
        self.assertEqual(expected[7], 'duplicatekey')
        self.assertEqual(len({x.split()[0] for x in expected[8:]}), 3)
        self.assertEqual(records[10]['variant'], 'added_present_empty')

    # Literal reproduction of the pinned nonempty span anchors the now-migrated C12 width policy.
    def test_privilege_width_policy(self):
        from state_privileges_oracle import wire
        from state_composition_oracle import capture
        source=(0,0,0,[0,0],[(1729,100000)])
        expected=bytes(20)+b'\1\xc1\6\0\0\xa0\x86\1'+bytes(5)
        self.assertEqual(wire(source),expected)
        self.assertEqual(capture(12,expected,(2,6,6,12)),'ok')

    # Maintainer policy selects vector-compatible compact gas exclusively, with no E8 fallback.
    def test_statistics_width_policy(self):
        from state_widths_oracle import statistics_wire
        from state_composition_oracle import capture
        source=([bytes(144),bytes(144)],[[0]*7+[100000],[0]*8],
            [(127,[0,0,0,128,0,0,0,0,0,0,256])])
        compact=statistics_wire(source,4,0)
        self.assertEqual(compact[297:300],b'\xc1\xa0\x86')
        self.assertEqual(capture(13,compact),'ok')
        self.assertNotEqual(capture(13,statistics_wire(source,4,8)),'ok')


# Literal checks require no compiler, native library, network or upstream generator.
if __name__ == '__main__':
    unittest.main()
