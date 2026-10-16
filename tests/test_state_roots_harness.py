"""Literal transport and unresolved state-width gates for complete mapping evidence."""
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

    # Nonempty STF evidence now supports E4/E8; the production migration must pass before closing this gate.
    @unittest.skip('Pending implementation: migrate C12 dictionary service/gas from natural to E4/E8; see spec/state-widths.md')
    def test_privilege_width_policy(self):
        self.fail('Replace this gate with passing E4/E8 production framing and the pinned nonempty reference checks.')

    # C13 natural-domain measures do not alone settle the bounded service-ID and gas-domain widths.
    @unittest.skip('Pending: migrate C13 service keys to E4; variable-width trace gas still conflicts with T fixed-width note')
    def test_statistics_width_policy(self):
        self.fail('Replace this gate with a normative width decision and complete-entry trace checks.')


# Literal checks require no compiler, native library, network or upstream generator.
if __name__ == '__main__':
    unittest.main()
