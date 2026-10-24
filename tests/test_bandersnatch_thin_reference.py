# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent test-only Draft 35 Thin equations and SHA-512 transcript.

Checks supplied input points, not hash-to-curve or ring membership. No production caller uses this
slow affine reference. Constants and procedures follow Draft 35 sections 1, 3 and Appendix A.
"""
import hashlib
import unittest

Q = 52435875175126190479447740508185965837690552500527637822603658699938581184513
ORDER = 13108968793781547619861935127046491459309155893440570251786403306729687672801
D = 45022363124591815672509500913686876175488063829319466900776701791074614335719
G = (18886178867200960497001835917649091219057080094937609519140440539760939937304,
     19188667384257783945677642223292697773471335439753913231509108946878080696678)
IDENTITY = (0, 1)
SUITE = b'Bandersnatch-SHA512-ELL2-v1'


def add(left, right):
    """Add checked twisted Edwards points using the complete affine group law."""
    x, y = left
    u, v = right
    product = D*x*u*y*v % Q
    return ((x*v+y*u)*pow(1+product, -1, Q) % Q,
            (y*v+5*x*u)*pow(1-product, -1, Q) % Q)


def multiply(point, scalar):
    """Compute a public test scalar product by ordinary double-and-add."""
    result = IDENTITY
    # Each bit contributes one double and optionally an addition, with no secret timing contract.
    while scalar:
        if scalar & 1:
            result = add(result, point)
        point = add(point, point)
        scalar >>= 1
    return result


def square_root(value):
    """Recover a field square root with Tonelli-Shanks, rejecting nonsquares."""
    if value == 0:
        return 0
    if pow(value, (Q-1)//2, Q) != 1:
        raise ValueError('nonsquare')
    odd, bits = Q-1, 0
    # Factor the field order into an odd part and a power of two.
    while odd % 2 == 0:
        odd //= 2
        bits += 1
    nonresidue = 2
    # Find a deterministic public quadratic nonresidue.
    while pow(nonresidue, (Q-1)//2, Q) != Q-1:
        nonresidue += 1
    c, root, residue = pow(nonresidue, odd, Q), pow(value, (odd+1)//2, Q), pow(value, odd, Q)
    # Reduce the remaining two-primary order until the square root is complete.
    while residue != 1:
        index, squared = 0, residue
        while squared != 1:
            squared = squared*squared % Q
            index += 1
        factor = pow(c, 1 << (bits-index-1), Q)
        root = root*factor % Q
        c = factor*factor % Q
        residue = residue*c % Q
        bits = index
    return root


def encode(point):
    """Encode y with arkworks' lexicographic x sign, rather than x parity."""
    x, y = point
    return (y | ((x > (Q-1)//2) << 255)).to_bytes(32, 'little')


def decode(raw):
    """Require one canonical compressed prime-subgroup point, including sign canonicality."""
    if len(raw) != 32:
        raise ValueError('point width')
    value = int.from_bytes(raw, 'little')
    y, sign = value & ((1 << 255)-1), value >> 255
    if y >= Q:
        raise ValueError('field encoding')
    x = square_root((y*y-1)*pow(D*y*y+5, -1, Q) % Q)
    if (x > (Q-1)//2) != bool(sign):
        x = -x % Q
    point = (x, y)
    if encode(point) != raw or multiply(point, ORDER) != IDENTITY:
        raise ValueError('noncanonical or non-subgroup point')
    return point


def squeeze(transcript, size):
    """Apply Appendix A.1 counter-mode SHA-512 with a little-endian u64 counter."""
    seed = hashlib.sha512(transcript).digest()
    return b''.join(hashlib.sha512(seed+i.to_bytes(8, 'little')).digest()
                    for i in range((size+63)//64))[:size]


def qualify(vector):
    """Reproduce public key, output, nonce commitment, response, equation and output hash."""
    v = {name: bytes.fromhex(value) for name, value in vector.items() if name != 'comment'}
    if any(len(v[name]) != 32 for name in ('sk', 'proof_s')):
        raise ValueError('scalar width')
    secret, response = (int.from_bytes(v[name], 'little') for name in ('sk', 'proof_s'))
    if not 0 < secret < ORDER or not 0 <= response < ORDER:
        raise ValueError('scalar encoding')
    public, inp, out, commitment = (decode(v[name]) for name in ('pk', 'h', 'gamma', 'proof_r'))
    if IDENTITY in (public, inp, out):
        raise ValueError('identity relation')
    assert public == multiply(G, secret)
    assert out == multiply(inp, secret)
    transcript = (SUITE+b'\x01'+(2).to_bytes(8, 'little')+encode(G)+v['pk']+v['h']+v['gamma']
                  +len(v['ad']).to_bytes(8, 'little')+v['ad'])
    coefficient = int.from_bytes(squeeze(transcript+b'\x30', 16), 'little')
    merged_input = add(G, multiply(inp, coefficient))
    merged_output = add(public, multiply(out, coefficient))
    expanded = squeeze(transcript+b'\x10'+v['sk'], 64)
    nonce = int.from_bytes(squeeze(transcript+b'\x11'+expanded, 48), 'little') % ORDER
    challenge = int.from_bytes(squeeze(transcript+b'\x40'+v['proof_r'], 16), 'little')
    assert commitment == multiply(merged_input, nonce)
    assert response == (nonce+challenge*secret) % ORDER
    assert multiply(merged_input, response) == add(commitment, multiply(merged_output, challenge))
    assert squeeze(SUITE+b'\x20'+v['gamma'], len(v['beta'])) == v['beta']
    return {'signature_bytes': len(v['gamma']+v['proof_r']+v['proof_s']), 'suite_bytes': len(SUITE)}


# One attributed known answer is sufficient for fixed regressions; migration checks consume all upstream vectors.
VECTOR = {
    'sk': 'c9922b7a9849b9928e15c655dd2f22ceef737cc355024f43d4b04bf4398c270d',
    'pk': '5a538209ff1fc7b1c9c8e1da05b3e169acf10a8b1591b3af029fe4eede0bbc71',
    'alpha': '', 'ad': '',
    'h': 'f508a4e84812ee3dce73ef72bb9064308128384b4801f81ef8616a7dffc486bc',
    'gamma': '54421f7ffc399872f1cb868efbb7eef4034178f1e369cebfb964ca61e4f3f256',
    'beta': '7b89f2aba6af7474694f24f75adf48336e00dcc8f3ac889ef4daa53c859497a6',
    'proof_r': 'd969c67f8fd97fcc8c0f8b129810ef5427786e319e304a056038caf32286d15e',
    'proof_s': '374e93cc0df1aaa3cbe7a66397213275e852717462f8a9b775ed8bcb68f45b00',
}


class ThinReferenceTests(unittest.TestCase):
    """Keep independent transcript/equation and canonicality regression witnesses."""

    def test_draft35_vector_one(self):
        """Reproduce Draft 35 Appendix C.2 vector 1 without arkworks or native code."""
        self.assertEqual(qualify(VECTOR), {'signature_bytes': 96, 'suite_bytes': 27})

    def test_complete_draft35_vectors(self):
        """Reproduce actual hash-to-curve and all signature bytes without loading native code."""
        import json
        from pathlib import Path
        from bandersnatch_thin_oracle import input_point, sign
        source = Path(__file__).resolve().parents[1]/'vendor/bandersnatch-vrf-spec/assets/vectors/bandersnatch_sha-512_ell2_thin.json'
        vectors = json.loads(source.read_text())
        self.assertEqual(len(vectors), 7)
        for vector in vectors:
            with self.subTest(vector=vector['comment']):
                alpha, ad = bytes.fromhex(vector['alpha']), bytes.fromhex(vector['ad'])
                self.assertEqual(encode(input_point(alpha)).hex(), vector['h'])
                proof, output = sign(int.from_bytes(bytes.fromhex(vector['sk']), 'little'), alpha, ad)
                self.assertEqual(proof.hex(), vector['gamma']+vector['proof_r']+vector['proof_s'])
                self.assertEqual(output.hex(), vector['beta'])

    def test_additional_data_is_bound(self):
        """The same points with different AD cannot retain the deterministic proof."""
        with self.assertRaises(AssertionError):
            qualify({**VECTOR, 'ad': '00'})

    def test_noncanonical_scalars_and_points(self):
        """Reject out-of-field scalars and duplicate identity sign encodings."""
        with self.assertRaises(ValueError):
            qualify({**VECTOR, 'proof_s': ORDER.to_bytes(32, 'little').hex()})
        with self.assertRaises(ValueError):
            qualify({**VECTOR, 'sk': VECTOR['sk']+'00'})
        # Each malformed point exercises a distinct canonical encoding rule.
        for encoded in (Q, 1 | (1 << 255)):
            with self.subTest(encoded=encoded), self.assertRaises(ValueError):
                decode(encoded.to_bytes(32, 'little'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
