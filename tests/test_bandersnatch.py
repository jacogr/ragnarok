#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build the pinned current Draft 35 Thin v1 Bandersnatch Rust ABI and check Nim.

Exposes suite, generated_proofs and bridge_checks, plus pinned fixture loading and native query
helpers.
"""
import ctypes
import hashlib
import json
from pathlib import Path
import platform
import random
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from native_dependencies import require_submodule
from build_bandersnatch import ROOT, BUILD, PINS
FIXTURES = ROOT / 'vectors/official/bandersnatch'


# Unmodified published vectors belong to their source submodule; small project reductions remain local fixtures.
def fixture_path(name):
    if name in ('thin.json','ring.json'):
        scheme=Path(name).stem
        return ROOT/PINS['sources']['spec-jam']['path']/f'assets/vectors/bandersnatch_sha-512_ell2_{scheme}.json'
    return FIXTURES/name


# Check reduced official fixtures against the complete immutable upstream JSON, without copying full STF states into Git.
def official_sources(fetch):
    entry=PINS['official_jam']
    upstream=require_submodule({'path':'vendor/jamtestvectors','repository':entry['repository'],'commit':entry['commit']},fetch)
    # Each reduced fixture retains only cryptographic inputs and independent expected outputs/roots.
    for local,remote in entry['files'].items():
        original=upstream/remote
        assert hashlib.sha256(original.read_bytes()).hexdigest()==entry['source_sha256'][local]
        v=json.loads(original.read_text());reduced=json.loads((ROOT/local).read_text())
        # Epoch-change padding checks the posterior pending ring rather than tickets from the prior epoch.
        if 'padding' in local:
            expected={'capacity':len(v['post_state']['gamma_k']),'root':v['post_state']['gamma_z'],
                      'members':[k['bandersnatch'] for k in v['post_state']['gamma_k']]}
        else:
            # These selected official cases start with an empty accumulator and accept every submitted ordered ticket.
            assert 'ok' in v['output'] and not v['pre_state']['gamma_a']
            tickets=[]
            assert len(v['input']['extrinsic'])==len(v['post_state']['gamma_a'])
            for ticket,score in zip(v['input']['extrinsic'],v['post_state']['gamma_a']):
                assert ticket['attempt']==score['attempt']
                tickets.append({**ticket,'output':score['id']})
            expected={'capacity':len(v['pre_state']['gamma_k']),'entropy':v['pre_state']['eta'][2],
                      'root':v['pre_state']['gamma_z'],'members':[k['bandersnatch'] for k in v['pre_state']['gamma_k']],
                      'tickets':tickets}
        assert expected==reduced, local


# Query one trusted fixture process with bounded public arguments; no secret material is logged by the runner.
def query(binary, command, *values):
    args = [v.hex() or '-' if isinstance(v,bytes) else str(v) for v in values]
    return subprocess.check_output([str(binary),command,*args],text=True,timeout=30).strip()


# Decode public fixture hex without retaining any source buffer reference.
def octets(value):
    return bytes.fromhex(value.removeprefix('0x'))


def ring_proof(v):
    return b''.join(octets(v[k]) for k in ['gamma','proof_pk_com','proof_r','proof_ok','proof_s','proof_sb','ring_proof'])


# Reject an invalid result and ensure the malformed-input path is not a caught backend panic.
def rejected(value):
    assert value.startswith('error:') and value!='error:7', value


# Verify public vectors, owned lifetimes, context separation and independent official tiny/full JAM tickets.
def suite(binary, query=query, failure_probe=None):
    assert query(binary,'O')=='ok'
    assert query(binary,'T')=='ok'
    # The caller can retain the exact contract failure alongside the ordinary query transcript.
    if failure_probe is None:
        failed = subprocess.run([str(binary),'F'],capture_output=True,text=True,timeout=30)
        code, diagnostic = failed.returncode, failed.stdout+failed.stderr
    else:
        code, diagnostic = failure_probe(binary)
    assert code == 1 and '[AssertionDefect]' in diagnostic and 'value.status == None' in diagnostic
    thin = json.loads(fixture_path('thin.json').read_text())
    rings = json.loads(fixture_path('ring.json').read_text())
    # Independently reproduce public equations and transcript fields before exercising the native backend.
    from test_bandersnatch_thin_reference import qualify
    for vector in thin:
        qualify(vector)
    # Ordinary contextual signatures must reproduce every published field exactly, not just verify themselves.
    for v in thin:
        sk,pk,context,ad = [octets(v[k]) for k in ('sk','pk','alpha','ad')]
        expected = octets(v['gamma'])+octets(v['proof_r'])+octets(v['proof_s'])
        assert query(binary,'P',sk)==pk.hex()
        assert query(binary,'S',sk,context,ad)==expected.hex()
        assert query(binary,'V',pk,expected,context,ad)==v['beta'][:64]
        rejected(query(binary,'V',pk,expected,context+b'!',ad))
        rejected(query(binary,'V',pk,expected,context,ad+b'!'))
    # Draft 35 permits identity R. Construct a zero-nonce proof only with the public fixture secret.
    from test_bandersnatch_thin_reference import SUITE, G, IDENTITY, ORDER, encode, squeeze
    vector = thin[0]
    transcript = (SUITE+b'\x01'+(2).to_bytes(8, 'little')+encode(G)+octets(vector['pk'])
                  +octets(vector['h'])+octets(vector['gamma'])+(0).to_bytes(8, 'little'))
    commitment = encode(IDENTITY)
    challenge = int.from_bytes(squeeze(transcript+b'\x40'+commitment, 16), 'little')
    response = (challenge*int.from_bytes(octets(vector['sk']), 'little') % ORDER).to_bytes(32, 'little')
    identity_r = octets(vector['gamma'])+commitment+response
    assert query(binary, 'V', octets(vector['pk']), identity_r, b'', b'') == vector['beta'][:64]
    # A second encoding of identity and an out-of-field response are never canonical proofs.
    for bad in (octets(vector['gamma'])+(1 | (1 << 255)).to_bytes(32, 'little')+response,
                identity_r[:64]+ORDER.to_bytes(32, 'little')):
        rejected(query(binary, 'V', octets(vector['pk']), bad, b'', b''))
    # Ring roots/proofs come from the published trusted-SRS vectors; generation uses the safe randomized backend feature set.
    for v in rings:
        proof = ring_proof(v)
        assert len(proof)==784 and len(octets(v['ring_pks_com']))==144
        assert query(binary,'R',8,octets(v['ring_pks']))==v['ring_pks_com']
        assert query(binary,'W',8,octets(v['ring_pks_com']),proof,octets(v['alpha']),octets(v['ad']))==v['beta'][:64]
    official = 0
    # The advanced pin restores positive independently published JAM tickets and exact outputs.
    for profile in ('tiny', 'full'):
        value = json.loads((FIXTURES/f'jam-{profile}.json').read_text())
        members = b''.join(octets(key) for key in value['members'])
        assert query(binary, 'R', value['capacity'], members) == value['root'][2:]
        for ticket in value['tickets']:
            context = b'jam_ticket_seal'+octets(value['entropy'])+bytes([ticket['attempt']])
            assert query(binary, 'W', value['capacity'], octets(value['root']),
                         octets(ticket['signature']), context, b'') == ticket['output'][2:]
            official += 1
    padding_case = json.loads((FIXTURES/'jam-padding.json').read_text())
    assert query(binary, 'R', padding_case['capacity'],
                 b''.join(octets(key) for key in padding_case['members'])) == padding_case['root'][2:]
    # Keep historical-source incompatibility explicit, separately from current vector success.
    historical = historical_profile_rejections(binary, query)
    v = rings[0]
    root,proof,members = octets(v['ring_pks_com']),ring_proof(v),octets(v['ring_pks'])
    rejected(query(binary,'W',256,root,proof,b'',b'')) # Domain 1024 cannot verify a domain-512 proof.
    rejected(query(binary,'W',8,root,proof,b'wrong-context',b''))
    rejected(query(binary,'W',8,root,proof,b'',b'wrong-additional'))
    rejected(query(binary,'W',8,root[:-1],proof,b'',b''))
    rejected(query(binary,'W',8,root,proof[:-1],b'',b''))
    # Membership proving cannot silently truncate rings or wrap/select an unrelated key index.
    rejected(query(binary,'G',8,octets(v['sk']),-1,members,b'',b''))
    rejected(query(binary,'G',8,octets(v['sk']),8,members,b'',b''))
    rejected(query(binary,'G',8,octets(v['sk']),0,members,b'',b''))
    rejected(query(binary,'R',1,members))
    rejected(query(binary,'R',8,members[:-1]))
    # Invalid encoded members are replaced by the specified padding point by the maintained wrapper.
    padding = octets(PINS['padding_point'])
    rejected(query(binary,'R',8,encode(IDENTITY)+members[32:])) # Valid identity is not rewritten as padding.
    altered = bytes([255])*32+members[32:]
    padded = padding+members[32:]
    assert query(binary,'R',8,altered)==query(binary,'R',8,padded)
    assert query(binary,'P',bytes(32)).startswith('error:')
    for n in (0,1,31,33):
        rejected(query(binary,'P',bytes(n)))
        rejected(query(binary,'V',bytes(n),bytes(96),b'',b''))
    return {'thin_vectors':len(thin),'ring_vectors':len(rings),'official_jam_tickets':official,'historical_profile':historical,
            'ownership':'passed','native_threads':4,'rounds_per_thread':32,'checked_failure':'passed'}


# These unchanged pinned fixtures belong to the former IETF suite, never current Thin success evidence.
def historical_profile_rejections(binary, query):
    rejected_tickets = 0
    # Exact original roots and tickets must not trigger a hidden historical-profile fallback.
    for profile in ('tiny', 'full'):
        value = json.loads((ROOT/f'vectors/historical/bandersnatch/jam-{profile}.json').read_text())
        members = b''.join(octets(key) for key in value['members'])
        assert query(binary, 'R', value['capacity'], members) != value['root'][2:]
        for ticket in value['tickets']:
            context = b'jam_ticket_seal'+octets(value['entropy'])+bytes([ticket['attempt']])
            rejected(query(binary, 'W', value['capacity'], octets(value['root']),
                           octets(ticket['signature']), context, b''))
            rejected_tickets += 1
    return {'status': 'incompatible_old_profile', 'rejected_tickets': rejected_tickets,
            'current_stf_parity': False}


# Cross-check proof creation and contextual output extraction through the supplied native owner.
def generated_proofs(binary, query=query):
    value = json.loads(fixture_path('ring.json').read_text())[0]
    members, secret, root = octets(value['ring_pks']), octets(value['sk']), octets(value['ring_pks_com'])
    proof = octets(query(binary,'G',8,secret,3,members,b'',b''))
    assert len(proof) == 784 and query(binary,'W',8,root,proof,b'',b'') == value['beta'][:64]
    # Deterministic public fixture scalars test contextual signing and output extraction, never production entropy.
    for i in range(1,17):
        scalar, context, additional = i.to_bytes(32,'little'), bytes(range(i)), b'additional'
        public = octets(query(binary,'P',scalar))
        signature = octets(query(binary,'S',scalar,context,additional))
        assert len(octets(query(binary,'V',public,signature,context,additional))) == 32
    return {'ring_proofs':1, 'thin_messages':16}


# Exercise exact widths, malformed points/scalars/roots and all-or-nothing writes at the Rust/C boundary.
def bridge_checks():
    library = BUILD / 'target/release' / ('libragnarok_bandersnatch.dylib' if platform.system()=='Darwin' else 'libragnarok_bandersnatch.so')
    lib = ctypes.CDLL(str(library));p = ctypes.c_void_p;s = ctypes.c_size_t
    lib.bs_verify.argtypes=[p,p,s,p,s,p,s,p];lib.bs_verify.restype=ctypes.c_uint32
    lib.bs_setup_new.argtypes=[s,ctypes.POINTER(p)];lib.bs_setup_new.restype=ctypes.c_uint32
    lib.bs_setup_free.argtypes=[p];lib.bs_setup_free.restype=None
    lib.bs_ring_verify.argtypes=[p,p,p,s,p,s,p,s,p];lib.bs_ring_verify.restype=ctypes.c_uint32
    lib.bs_key_new.argtypes=[p,s,ctypes.POINTER(p)];lib.bs_key_new.restype=ctypes.c_uint32
    holder = p(0x1234)
    assert lib.bs_key_new(None,32,ctypes.byref(holder))==1 and holder.value==0x1234
    output = (ctypes.c_ubyte*32)(*[0xa5]*32)
    # Every wrong ordinary/ring proof length must fail before reading any claimed proof bytes.
    for width in range(100):
        # The sole valid width is exercised by the independent known-answer suites.
        if width!=96:
            assert lib.bs_verify(None,None,width,None,0,None,0,output)==1
    for width in range(786):
        # All other anonymous proof widths fail before borrowing the purported proof.
        if width!=784:
            assert lib.bs_ring_verify(None,None,None,width,None,0,None,0,output)==1
    assert bytes(output)==bytes([0xa5])*32
    owner=p();assert lib.bs_setup_new(8,ctypes.byref(owner))==0
    try:
        # A malformed proof must leave the caller output untouched on every rejection.
        v = json.loads(fixture_path('ring.json').read_text())[0];proof = ring_proof(v);root = octets(v['ring_pks_com'])
        rng = random.Random(784)
        for _ in range(64):
            mutated = bytearray(proof);index = rng.randrange(len(mutated));mutated[index]^=1<<rng.randrange(8)
            status = lib.bs_ring_verify(owner,root,bytes(mutated),784,None,0,None,0,output)
            assert status not in (0,6),status
            assert bytes(output)==bytes([0xa5])*32
        assert lib.bs_ring_verify(owner,root,proof,784,None,65537,None,0,output)==1
    finally:
        # Release the native SRS owner even if an ABI assertion discovers a regression.
        lib.bs_setup_free(owner)
    return {'ordinary_wrong_widths':99,'ring_wrong_widths':785,'mutated_ring_proofs':64}
