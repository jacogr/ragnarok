"""Independent safeguard for the original full-report credential bindings, before native execution."""
import hashlib
import json
import unittest
from report_fixtures import composition_cases, fixtures


# Credential fixture construction must preserve exact original bytes, mutations and native expectations.
class ReportSignatureHarness(unittest.TestCase):
    # Freeze all 63 original cases, including independently signed ordinary credentials and expected verdicts.
    def test_original_identity(self):
        provider, values = fixtures()
        cases = composition_cases(values)
        serialized = [dict(name=c['name'], wire=c['wire'].hex(),
                           credentials=[[a.hex(), b.hex()] for a, b in c['credentials']],
                           wanted=c['wanted']) for c in cases]
        identity = hashlib.sha256(json.dumps(serialized, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.assertTrue(provider.startswith('OpenSSL'))
        self.assertEqual(len(values), 7)
        self.assertEqual(len(cases), 63)
        self.assertEqual(sum(c['wanted'] for c in cases), 7)
        self.assertEqual(identity, '14838e43aace5a7544b36a87d69c12fa271f4f712940d5e6117edac5ea3583fd')

    # Hand-authored fields verify physical mutation offsets independently of the corpus's signature provider.
    def test_literal_mutations(self):
        wire = bytearray(300)
        wire[68:70] = (6).to_bytes(2, 'little')
        credentials = [(bytes(32), bytes(64)), (bytes([1])*32, bytes([2])*64)]
        value = dict(name='literal', wire=bytes(wire), credentials=credentials,
                     wrong_domain=(bytes(32), bytes([3])*64))
        cases = {c['name'].removeprefix('literal-'): c for c in composition_cases([value])}
        self.assertEqual(set(cases), {'valid', 'signature-0', 'signature-1', 'report-hash',
                                     'shards', 'anchor-slot', 'lookup-state', 'wrong-domain', 'swapped-keys'})
        self.assertEqual(cases['shards']['wire'][68:70], (9).to_bytes(2, 'little'))
        self.assertEqual(cases['anchor-slot']['wire'][136], 1)
        self.assertEqual(cases['lookup-state']['wire'][240], 1)
        self.assertEqual(cases['report-hash']['wire'][0], 1)
        self.assertEqual(cases['signature-0']['credentials'][0][1], b'\x01'+bytes(63))
        self.assertEqual(cases['signature-1']['credentials'][1][1], b'\x03'+bytes([2])*63)
        self.assertEqual(cases['swapped-keys']['credentials'],
                         [(credentials[1][0], credentials[0][1]), (credentials[0][0], credentials[1][1])])
        self.assertEqual(cases['wrong-domain']['credentials'][0], value['wrong_domain'])
        self.assertEqual(value['wire'], bytes(wire))
        self.assertEqual(value['credentials'], credentials)


# This harness authors public test fixtures only and never builds a compiler or invokes a native peer.
if __name__ == '__main__':
    unittest.main()
