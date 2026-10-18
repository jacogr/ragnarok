# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent test-only assurance transcripts and ordinary OpenSSL credential fixtures.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import hashlib
from functools import lru_cache
from assurances_oracle import ROOT, logical, record, record_error, config_error, token
from report_fixtures import openssl_sign, validate_provider


# Hash the exact fixed-field transcript with the 32-byte Blake2b parameterization.
def message(parent, bits, cores):
    return b'jam_available'+hashlib.blake2b(parent+bits[:(cores+7)//8],digest_size=32).digest()


# Model only message-builder constraints; validator/parent relationships belong to verification.
def message_result(parent, bits, cores):
    # Invalid core count must fail before profile width or bit indexing.
    if not 1 <= cores <= 341:
        return 'invalidconfig'
    # The existing independent canonicality oracle validates all 43 native bitset octets.
    if record_error((parent,bits,0,bytes(64)),cores,1,None):
        return 'noncanonical'
    return message(parent,bits,cores).hex()


# Cache ordinary independent signatures so maximum-count cases need only three test credentials.
@lru_cache(maxsize=None)
def credential(index, signed):
    seed=hashlib.sha256(f'ragnarok-public-assurance-test-seed-{index}'.encode()).digest()
    return openssl_sign(seed,signed)


# Validate shared context completely before considering any cryptographic verdict.
def structural(cores, validators, parent, keys, values):
    error=config_error(cores,validators)
    # Configuration determines every subsequent resource and key-index domain.
    if error:
        return error
    # A partial or oversized set cannot authorize a different validator mapping accidentally.
    if len(keys)!=validators:
        return 'invalidkeyset'
    # Resource policy applies before inspecting individual indices.
    if len(values)>validators:
        return 'limitexceeded'
    previous=None
    # Check the whole sequence before a deliberately invalid earlier signature can hide late errors.
    for value in values:
        error=record_error(value,cores,validators,previous)
        # Preserve validator/order/padding precedence from the structural codec.
        if error:
            return error
        # Every assurance must bind to the externally supplied parent.
        if value[0]!=parent:
            return 'wrongparent'
        previous=value[2]
    return None


# Prepare immutable equivalent test requests before the first native implementation handoff.
def requests():
    provider=validate_provider()
    lines=[];expected=[]
    parent=bytes(range(32))
    # Message checks never obtain expected bytes from a peer implementation.
    def add_message(cores,bits,anchor=parent):
        lines.append(f'M {cores} {anchor.hex()} {bits.hex()}')
        expected.append(message_result(anchor,bits,cores))
    # Verification expectations come from known independently signed or deliberately corrupted credentials.
    def add_verify(cores,validators,anchor,keys,values,verdict='ok'):
        lines.append(f'V {cores} {validators} {anchor.hex()} {token(b"".join(keys))} {token(logical(values))}')
        error=structural(cores,validators,anchor,keys,values)
        expected.append(error or (f'ok {len(values)}' if verdict=='ok' else verdict))
    # Exercise each bit of each representative aligned/unaligned width in the native message builder.
    for cores in (1,2,7,8,9,15,16,17,255,256,257,340,341):
        add_message(cores,bytes(43))
        add_message(cores,record(0,cores,7)[1])
        # Single-bit identities expose byte and bit-order errors independently from signatures.
        for bit in range(cores):
            bits=bytearray(43);bits[bit//8]=1<<(bit%8)
            add_message(cores,bytes(bits))
        width=(cores+7)//8
        # Partial final octets must reject high bits rather than hashing a noncanonical message.
        if cores%8:
            bits=bytearray(43);bits[width-1]=1<<(cores%8)
            add_message(cores,bytes(bits))
        # Native storage outside the profile cannot be silently ignored by the message API.
        if width<43:
            bits=bytearray(43);bits[width]=1
            add_message(cores,bytes(bits))
    # Invalid configurations retain their unsigned domain, including UInt64 maximum.
    for cores in (0,342,2**64-1):
        add_message(cores,bytes(43))
    # Shared ordinary credentials cover real tiny/full profiles and intermediate wire-width edges.
    for cores,validators in ((2,6),(341,1023),(341,6),(8,6),(9,9),(340,1020)):
        bits=record(0,cores,4)[1]
        signed=message(parent,bits,cores)
        pairs=[credential(i,signed) for i in range(3)]
        keys=[pairs[i%3][0] for i in range(validators)]
        values=[(parent,bits,i,pairs[i%3][1]) for i in (0,1,validators-1)]
        # All population boundaries use the same independently signed native-domain records.
        for subset in ([],values[:1],values,[(parent,bits,i,pairs[i%3][1]) for i in range(validators)]):
            add_verify(cores,validators,parent,keys,subset)
        # Exact key-set length is checked even for an empty extrinsic.
        add_verify(cores,validators,parent,keys[:-1],[])
        add_verify(cores,validators,parent,keys+[keys[0]],values)
        add_verify(cores,validators,parent,keys,values*(validators//3+1))
        # Distinct key positions must be selected by validator index, including the last full validator.
        wrong_keys=list(keys);wrong_keys[1]=pairs[0][0]
        add_verify(cores,validators,parent,wrong_keys,values,'invalidsignature')
        changed=list(values);last=list(changed[-1]);last[3]=bytes(64);changed[-1]=tuple(last)
        add_verify(cores,validators,parent,keys,changed,'invalidsignature')
        # Wrong domains and wrong hashed field framing remain cryptographically invalid despite valid structure.
        for alternative in (b'jam_guarantee'+signed[13:],b'$jam_available'+signed[13:],
                            b'jam_available'+hashlib.blake2b(parent+b'\x01'+bits[:(cores+7)//8],digest_size=32).digest(),
                            b'jam_available'+hashlib.blake2b(parent+bits[:(cores+7)//8]).digest()[:32]):
            changed=list(values);value=list(changed[0]);value[3]=credential(0,alternative)[1];changed[0]=tuple(value)
            add_verify(cores,validators,parent,keys,changed,'invalidsignature')
        # Parent mismatch must precede an already invalid earlier signature.
        changed=list(values);value=list(changed[0]);value[3]=bytes(64);changed[0]=tuple(value)
        last=list(changed[-1]);last[0]=bytes([99])*32;changed[-1]=tuple(last)
        add_verify(cores,validators,parent,keys,changed)
        # Validator limits, ordering and padding are checked on caller-constructed values too.
        for index in (validators,65535,0):
            changed=list(values);value=list(changed[-1]);value[2]=index;changed[-1]=tuple(value)
            add_verify(cores,validators,parent,keys,changed)
        changed=[values[1],values[0]];add_verify(cores,validators,parent,keys,changed)
        # Change one legal bit while retaining the old signature, proving message content binding.
        changed=list(values);value=list(changed[-1]);altered=bytearray(value[1]);altered[0]^=1;value[1]=bytes(altered);changed[-1]=tuple(value)
        add_verify(cores,validators,parent,keys,changed,'invalidsignature')
        width=(cores+7)//8
        # Invalid unused storage is a structural failure even when all signature bytes are ordinary.
        if width<43:
            changed=list(values);value=list(changed[-1]);altered=bytearray(value[1]);altered[width]=1;value[1]=bytes(altered);changed[-1]=tuple(value)
            add_verify(cores,validators,parent,keys,changed)
        # Each signature byte is independently corrupted; these are not exceptional-point policy fixtures.
        for position in range(64):
            changed=list(values);value=list(changed[-1]);signature=bytearray(value[3]);signature[position]^=1;value[3]=bytes(signature);changed[-1]=tuple(value)
            add_verify(cores,validators,parent,keys,changed,'invalidsignature')
    # Configuration rejection must precede key-set length and empty-record handling.
    for cores,validators in ((0,6),(1,6),(342,6),(2,0),(2,3),(2,5),(2,7),(2,9),(341,1022),(2,1024),(2**64-1,6),(2,2**64-1)):
        add_verify(cores,validators,parent,[],[])
    return provider,lines,expected
