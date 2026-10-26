# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Test-only Draft 35 v1 Elligator2, Thin signing and output equations.

Uses RFC9380 sections 5.3.1/6.8.2 and Appendix D with the recorded v1 48-byte prefix deviation.
The Montgomery coefficients follow from the Edwards a=-5,d constants. Arkworks 0.6's Elligator2
configuration supplies Z=5 and the specified square-branch sign convention. This slow reference
never handles production secrets and never invokes the native backend.
"""
from functools import lru_cache
import hashlib
from test_bandersnatch_thin_reference import (Q, D, G, ORDER, SUITE, IDENTITY, add, multiply,
                                            encode, square_root, squeeze)


def elligator(value):
    """Map one public field element through Montgomery form to twisted Edwards form."""
    a = -5 % Q
    j = 2*(a+D)*pow(a-D, -1, Q) % Q
    k = 4*pow(a-D, -1, Q) % Q
    ratio = j*pow(k, -1, Q) % Q
    inverse_k_squared = pow(k*k, -1, Q)
    denominator = (1+5*value*value) % Q
    first = -ratio*pow(denominator or 1, -1, Q) % Q
    def rhs(x):
        """Evaluate the normalized Montgomery equation for the candidate abscissa."""
        return (x*x*x+ratio*x*x+x*inverse_k_squared) % Q
    first_square = pow(rhs(first), (Q-1)//2, Q) == 1
    x = first if first_square else (-first-ratio) % Q
    y = square_root(rhs(x))
    # The suite's branch convention chooses odd y for the first square, even otherwise.
    if bool(y & 1) != first_square:
        y = -y % Q
    s, t = x*k % Q, y*k % Q
    # The rational map's exceptional denominator maps to the Edwards identity before cofactor clearing.
    if (s+1)*t % Q == 0:
        return IDENTITY
    return (s*pow(t, -1, Q) % Q, (s-1)*pow(s+1, -1, Q) % Q)


def input_point(data):
    """Expand two 48-byte big-endian field elements with v1 XMD, map, add and clear cofactor."""
    dst = SUITE+b'\x60'
    prime = dst+bytes([len(dst)])
    b0 = hashlib.sha512(bytes(48)+data+(96).to_bytes(2, 'big')+b'\0'+prime).digest()
    b1 = hashlib.sha512(b0+b'\1'+prime).digest()
    b2 = hashlib.sha512(bytes(x^y for x, y in zip(b0, b1))+b'\2'+prime).digest()
    uniform = (b1+b2)[:96]
    first, second = (int.from_bytes(uniform[n:n+48], 'big') % Q for n in (0, 48))
    return multiply(add(elligator(first), elligator(second)), 4)


def secret_from_seed(seed):
    """Independent Draft 35 A.3 public-fixture key generation with explicit nonzero retry."""
    if len(seed) != 32:
        raise ValueError('seed width')
    reduced = (int.from_bytes(seed,'little') % ORDER).to_bytes(32,'little')
    for counter in range(256):
        # Each retry starts a fresh suite transcript and appends a single counter octet.
        transcript = SUITE+seed+(bytes([counter]) if counter else b'')
        expanded = squeeze(transcript+b'\x10'+reduced,64)
        scalar = int.from_bytes(squeeze(transcript+b'\x11'+expanded,48),'little') % ORDER
        if scalar:
            return scalar
    raise ValueError('all secret derivation candidates were zero')


def sign(secret, data, ad):
    """Produce one test signature and output from an explicit public fixture scalar, never a seed."""
    if not 0 < secret < ORDER:
        raise ValueError('fixture scalar outside nonzero canonical domain')
    # Only exact immutable fixture inputs enter the bounded process-local cache. Other accepted
    # bytes-like inputs retain their original calculation and errors, including after mutation.
    if type(secret) is int and type(data) is bytes and type(ad) is bytes:
        return _sign(secret, data, ad)
    return _sign.__wrapped__(secret, data, ad)


@lru_cache(maxsize=4096)
def _sign(secret, data, ad):
    """Memoize deterministic public-fixture results; no native output or production secret enters this cache."""
    h = input_point(data)
    o, pk = multiply(h, secret), multiply(G, secret)
    t = (SUITE+b'\1'+(2).to_bytes(8, 'little')+encode(G)+encode(pk)+encode(h)+encode(o)
         +len(ad).to_bytes(8, 'little')+ad)
    z = int.from_bytes(squeeze(t+b'\x30', 16), 'little')
    expanded = squeeze(t+b'\x10'+secret.to_bytes(32, 'little'), 64)
    k = int.from_bytes(squeeze(t+b'\x11'+expanded, 48), 'little') % ORDER
    r = multiply(add(G, multiply(h, z)), k)
    c = int.from_bytes(squeeze(t+b'\x40'+encode(r), 16), 'little')
    return (encode(o)+encode(r)+((k+c*secret) % ORDER).to_bytes(32, 'little'),
            squeeze(SUITE+b'\x20'+encode(o), 32))
