# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP 0.8.0 state-key/node byte equations; historical singleton roots are labelled compatibility only."""
import hashlib
import json
import random
import subprocess
from test_support import ROOT

MAX=2**64-1


# Test hashes use Python's independent standard Blake2b-256 implementation, never the production native bridge.
def digest(value):
    return hashlib.blake2b(value,digest_size=32).digest()


# Empty preimages/inline values need one token in the trusted batch protocol.
def token(value):
    return value.hex() or '-'


# C(i) places an E1 chapter at the start of a 31-octet zero-initialized state key.
def chapter_key(chapter):
    return bytes([chapter])+bytes(30)


# C(i,s) interleaves E4 little-endian service octets with zeroes after the chapter.
def chapter_service(chapter,service):
    octets=service.to_bytes(4,'little')
    return bytes([chapter])+b''.join(bytes([octet,0]) for octet in octets)+bytes(22)


# C(s,h) hashes the exact raw preimage and retains digest bytes 0..26 around four service octets.
def service_key(service,preimage):
    octets=service.to_bytes(4,'little');hashed=digest(preimage)
    return b''.join(bytes([n,a]) for n,a in zip(octets,hashed[:4]))+hashed[4:27]


# B keeps the low 255 bits of the full left identity plus all right identity bits, with no $node prefix.
def branch(left,right):
    return bytes([left[0]&127])+left[1:]+right


# L has exact headers 80..a0 or c0, a 31-octet key and one padded value/hash half.
def leaf(key,value):
    return (bytes([128+len(value)])+key+value+bytes(32-len(value))) if len(value)<=32 else b'\xc0'+key+digest(value)


# Fixed-value encoder observations include both exact node bytes and independently computed node identity.
def emitted(encoded):
    return encoded.hex()+' '+digest(encoded).hex()


# A node decoder copies one canonical 64-byte prefix; malformed/reserved padding never becomes a second encoding.
def decode(data):
    # Complete node width precedes discriminators or partial metadata, including malformed first octets.
    if len(data)<64:
        return 'truncated'
    data=data[:64];header=data[0]
    # A branch's decoded left field is explicitly a truncated commitment, not a reconstructed complete hash.
    if header<128:
        fields='B '+data[:32].hex()+' '+data[32:].hex()
    elif header<192:
        # Embedded lengths above 32 and nonzero unused suffixes have no encoder image.
        length=header&63
        if length>32 or any(data[32+length:]):
            return 'noncanonical'
        fields='E '+data[1:32].hex()+' '+str(length)+' '+token(data[32:32+length])
    else:
        # Regular leaf flags reserve their remaining six bits, which must all be zero.
        if header!=192:
            return 'noncanonical'
        fields='H '+data[1:32].hex()+' '+data[32:].hex()
    return '64 '+fields+' '+data.hex()


# Hashing nominal encoded bytes must retain canonicality checks rather than accepting arbitrary fixed-width blobs.
def hash_node(data):
    checked=decode(data)
    return checked if checked in ('truncated','noncanonical') else digest(data[:64]).hex()


# Metadata preflight validates the source's exact logical inline length/padding, not only a decodable output projection.
def embedded_source(key,length,storage):
    # No oversized length may select a partial field or access beyond copied fixed storage.
    if length>32 or any(storage[length:]):
        return 'noncanonical'
    return emitted(bytes([128+length])+key+storage)


# Read frozen upstream data as a Git blob without executing its historical generator or altering sparse checkout paths.
def legacy_singletons():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    data=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':trie/trie.json'])
    assert hashlib.sha256(data).hexdigest()==pins['git_blobs']['trie/trie.json']
    result=[]
    # Historical input keys have 32 bytes; only singleton cases permit this explicit last-octet projection compatibility check.
    for item in json.loads(data):
        if len(item['input'])==1:
            key,value=next(iter(item['input'].items()));key=bytes.fromhex(key);value=bytes.fromhex(value)
            assert len(key)==32
            projected=key[:31]
            assert digest(leaf(projected,value)).hex()==item['output']
            result.append((projected,value,item['output']))
    return result


# Deterministic sources and hostile headers/padding provide independent wire/field/hash expectations before native execution.
def requests():
    lines,expected=[],[]

    # Every complete node observation is independent of native encode/decode round trips.
    def dec(data):
        lines.append('D '+token(data));expected.append(decode(data))

    # Explicit logical leaf sources are independent of metadata decoded by the production implementation.
    def enc_leaf(key,value,limit=MAX):
        lines.append(f'L {key.hex()} {limit} {token(value)}')
        expected.append('limitexceeded' if len(value)>limit else emitted(leaf(key,value)))

    # Metadata encoding is tested directly as well as through round-trip supplementary native checks.
    def meta_inline(key,length,storage):
        lines.append(f'ME {key.hex()} {length} {storage.hex()}');expected.append(embedded_source(key,length,storage))

    # All chapter values are structural namespace octets, not a prematurely hardcoded list of currently assigned chapters.
    for chapter in range(256):
        lines.append(f'C {chapter}');expected.append(chapter_key(chapter).hex())
        # E4 source index boundary patterns expose both endianness and interleaving positions.
        for service in (0,1,255,256,65535,65536,0x01020304,2**32-1):
            lines.append(f'S {chapter} {service}');expected.append(chapter_service(chapter,service).hex())
    key=bytes(range(31))
    # Every inline/hash threshold and cryptographic input-block boundary uses distinct raw source patterns.
    for length in (0,1,2,7,31,32,33,63,64,127,128,129,255,256,1024,16384):
        value=bytes(i%251 for i in range(length));node=leaf(key,value)
        enc_leaf(key,value);dec(node+b'ignored')
        # Tight limits apply before hashing/copying, while exact limits must succeed.
        for limit in sorted({0,max(0,length-1),length}):
            enc_leaf(key,value,limit)
        # Proper node truncations must never expose an earlier key, header or partial value/hash.
        for cut in range(64):
            dec(node[:cut])
        # Raw preimage hashing adds no length discriminator, namespace marker or implicit protocol prefix.
        for service in (0,1,0x01020304,2**32-1):
            for limit in sorted({0,max(0,length-1),length,MAX}):
                lines.append(f'K {service} {limit} {token(value)}')
                expected.append('limitexceeded' if length>limit else service_key(service,value).hex())
    # Exhaust all node header bytes with zero bodies to identify precise branch/inline/reserved/hashed partitions.
    for header in range(256):
        node=bytes([header])+bytes(63);dec(node)
        lines.append('HB '+node.hex());expected.append(hash_node(node))
        left=bytes([header])+bytes(range(1,32));right=bytes([255-header])*32
        encoded=branch(left,right)
        lines.append(f'B {left.hex()} {right.hex()}');expected.append(emitted(encoded))
        lines.append(f'MB {left.hex()} {right.hex()}')
        expected.append('noncanonical' if header>=128 else emitted(encoded))
        # Source embedded lengths are independently checked even when supplied through nominal uint8 metadata.
        meta_inline(key,header,bytes(32))
    # Every unused padding position is checked, including both low and high bit pollution in the final value half.
    for length in range(33):
        storage=bytes(range(length))+bytes(32-length);meta_inline(key,length,storage)
        # Padding pollution must fail both raw decoding/hash and independent metadata encoding.
        for position in range(length,32):
            for octet in (1,128,255):
                changed=bytearray(storage);changed[position]=octet
                meta_inline(key,length,bytes(changed))
                node=bytes([128+length])+key+changed;dec(node)
                lines.append('HB '+node.hex());expected.append('noncanonical')
    # Historical roots are compatibility evidence only, after projecting their legacy 32-byte input keys to current 31-byte keys.
    for projected,value,root in legacy_singletons():
        enc_leaf(projected,value);dec(leaf(projected,value))
        lines.append('HB '+leaf(projected,value).hex());expected.append(root)
    rng=random.Random(0x53544154454c4159)
    # Random complete/truncated records probe fixed-copy decoders without input-derived allocation or unbounded traversal.
    for _ in range(1800):
        data=rng.randbytes(rng.randrange(90));dec(data)
        # Complete raw nominal encodings must also validate before hashing.
        if len(data)>=64:
            lines.append('HB '+data[:64].hex());expected.append(hash_node(data[:64]))
    # Arbitrary regular-leaf metadata keeps its value hash role without claiming a corresponding long preimage is available.
    for _ in range(100):
        key=rng.randbytes(31);hashed=rng.randbytes(32);node=b'\xc0'+key+hashed
        lines.append(f'MH {key.hex()} {hashed.hex()}');expected.append(emitted(node));dec(node)
    return lines,expected
