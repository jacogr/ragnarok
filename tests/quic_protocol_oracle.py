# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent arbitrary-precision SAN/framing expectations and real certificate-policy fixtures.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import random
import subprocess


# Literal pinned radix-32 identity formula, independent of the native implementation's bit grouping.
def name(key):
    n = int.from_bytes(key, 'little')
    alphabet = '$abcdefghijklmnopqrstuvwxyz234567'
    return '$e'+''.join(alphabet[(n//(32**i)) % 32] for i in range(52))


# Return only a reason on malformed/pending input; successful metadata is exact and FIN-bound.
def frame(wire, request, maximum, fin):
    # Invalid local admission policy cannot turn a malformed input into a usable extent.
    if maximum < 0:
        return '3'
    start = int(request)
    # The first request byte must identify CE 143 before parsing its header.
    if request and wire and wire[0] != 143:
        return '5'
    # Partial headers can remain pending only while the sender has not ended the stream.
    if len(wire) < start+4:
        return '4' if fin else '2'
    length = int.from_bytes(wire[start:start+4], 'little')
    # Compare in arbitrary precision before any host-sized conversion.
    if length > maximum:
        return '6'
    extent = start+4+length
    # A second message or trailing byte is never part of this direction.
    if len(wire) > extent:
        return '7'
    # Complete bytes without FIN remain pending rather than exposing successful metadata.
    if not fin:
        return '2'
    # Premature FIN rejects the claimed payload, including a truncated final byte.
    if len(wire) != extent:
        return '4'
    return f'ok {length} {extent}'


# Assemble the complete independent corpus without loading the production Nim module or a native verifier.
def requests(folder):
    lines, expected = [], []
    groups = dict(names=0, lengths=0, frames=0, certificates=0, malformed_der=0)
    # Every request has an exact standalone expected response and a stable group count.
    def add(group, operation, values, answer):
        values = [(v.hex() or '-') if isinstance(v, bytes) else str(v) for v in values]
        lines.append(' '.join([operation, *values]))
        expected.append(answer)
        groups[group] += 1
    # Exercise every individual public-key bit, both extremes and reproducible unrelated keys.
    rng = random.Random(143)
    keys = [bytes(32), bytes([255])*32]+[(1 << i).to_bytes(32, 'little') for i in range(256)]
    keys += [rng.randbytes(32) for _ in range(64)]
    for key in keys:
        add('names', 'N', [key], name(key))
    # Header widths, signed ceilings and unsigned E4 boundaries are checked independently of host conversion.
    for maximum in (-1, 0, 1, 32, 1024, 2**32-1, 2**63-1):
        for raw in (b'', b'\0', b'\0'*3, b'\0'*5, *(v.to_bytes(4, 'little') for v in (0, 1, 31, 32, 1024, 1025, 2**31, 2**32-1))):
            answer = '3' if maximum < 0 else '4' if len(raw) != 4 else '6' if int.from_bytes(raw,'little') > maximum else f'ok {int.from_bytes(raw,"little")}'
            add('lengths', 'L', [maximum, raw], answer)
    # Every prefix, missing FIN, trailing bytes and wrong selector retain the original framing expectations.
    for request in (False, True):
        for size in (0, 1, 3, 32, 255):
            wire = (b'\x8f' if request else b'')+size.to_bytes(4,'little')+bytes(i % 251 for i in range(size))
            variants = [wire[:i] for i in range(len(wire)+1)]+[wire+b'\0', b'\x90'+wire[1:]]
            for raw in variants:
                for fin in (False, True):
                    add('frames', 'F', [int(request), int(fin), 1024, raw], frame(raw,request,1024,fin))
        # Advertised huge sizes require no attacker-sized allocation.
        for size in (32, 1025, 2**31, 2**32-1):
            raw = (b'\x8f' if request else b'')+size.to_bytes(4,'little')
            for maximum in (-1, 0, 32, 1024, 2**63-1):
                for fin in (False, True):
                    add('frames','F',[int(request),int(fin),maximum,raw],frame(raw,request,maximum,fin))
    # Reproduce all original xorshift inputs with explicitly masked arbitrary-precision arithmetic.
    state, mask = 0x51554943, 2**64-1
    for iteration in range(10000):
        raw = bytearray()
        for _ in range(128):
            state = (state ^ (state << 13)) & mask
            state = (state ^ (state >> 7)) & mask
            state = (state ^ (state << 17)) & mask
            raw.append(state & 255)
        raw = bytes(raw[:iteration % 129])
        request, fin = iteration % 2 == 0, iteration % 3 == 0
        maximum = 32 if request else 1024
        add('frames','F',[int(request),int(fin),maximum,raw],frame(raw,request,maximum,fin))
        add('malformed_der','D',[b'',raw],'0')
    # Existing generated fixtures isolate identity mismatch, SAN cardinality and key/signature algorithms.
    for identity in ('a','b','c','d','e','wrong-san','no-san','multi-san','ecdsa','wrong-signature'):
        der = subprocess.check_output(['openssl','x509','-in',str(folder/f'{identity}.cert.pem'),'-outform','DER'])
        key = (folder/f'{identity}.pub').read_bytes()
        valid = identity in ('a','b','c','d','e')
        for pin in (b'', key, bytes([key[0]^1])+key[1:], key[:-1], key+b'\0'):
            add('certificates','D',[pin,der],str(int(valid and pin in (b'',key))))
        if valid:
            # Mutate exact SAN content while preserving DER lengths; identity policy must reject NUL/altered names.
            san = name(key).encode()
            assert der.count(san) == 1
            offset = der.index(san)
            for index in (0, 2, 53):
                mutated = der[:offset+index]+b'\0'+der[offset+index+1:]
                add('certificates','D',[b'',mutated],'0')
        # Exact DER consumption rejects every truncation and trailing byte/certificate.
        for n in range(len(der)):
            add('certificates','D',[b'',der[:n]],'0')
        add('certificates','D',[b'',der+b'\0'],'0')
        add('certificates','D',[b'',der+der],'0')
    add('certificates','D',[b'',bytes(8193)],'0')
    return lines, expected, groups
