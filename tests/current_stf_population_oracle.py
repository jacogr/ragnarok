# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map culprit admission, delayed null filtering and six/nine roster rotations.

Only the original ring commitments are native input witnesses. OpenSSL signs the public culprit
seed independently of dalek; mathematical Thin and complete-map equations calculate all outputs.
"""
import hashlib
import json
from pathlib import Path
from current_stf_epoch_oracle import (FIXTURE as EPOCH_FIXTURE, PUBLIC, NULL_VALIDATOR,
                                      consensus, roster, successor)
from current_stf_oracle import decode_checkpoint, checkpoint, tree
from state_layout_oracle import chapter_key
from state_statistics_oracle import wire as statistics_wire
from state_privileges_oracle import wire as privileges_wire
from report_fixtures import openssl_sign, validate_provider
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-population.json'
SLOTS = (2, 11, 12, 13, 24, 25)


def original(fixture):
    """Reconstruct every changed original chapter independently of the native fixture constructor."""
    baseline = json.loads(EPOCH_FIXTURE.read_text())
    parent = decode_checkpoint(bytes.fromhex(baseline['parent_checkpoint']))
    public = {secret: key for key, secret in PUBLIC.items()}
    records = []
    # Independent public keys and deliberately nonzero opaque fields expose partial null filtering.
    for index in range(9):
        ed, _ = openssl_sign(bytes([index+11])+bytes(31), b'fixture-public-key')
        records.append(public[index+1]+ed+bytes([index+1])*144+bytes([20+index])*128)
    active, staging = records[:6], list(reversed(records[:6]))
    pending, previous = records[1:]+records[:1], records[2:]+records[:2]
    captured = decode_checkpoint(bytes.fromhex(fixture['parent_checkpoint']))
    # KZG roots are fixed input witnesses; no other parent byte is accepted from the native builder.
    root = consensus(captured[chapter_key(4)])[1]
    parent[chapter_key(4)] = (natural(9)+b''.join(pending)+root+b'\1'
                            +b''.join(active[i % 6][:32] for i in range(12))+b'\0')
    # Each counted sequence has its own GP population, independent of the decoder ceiling.
    for chapter, rows in ((7, staging), (8, active), (9, previous)):
        parent[chapter_key(chapter)] = natural(len(rows))+b''.join(rows)
    parent[chapter_key(1)] = (b'\1'+bytes(32))*3
    parent[chapter_key(2)] = bytes(3*80*32)
    parent[chapter_key(10)] = bytes(3)
    parent[chapter_key(12)] = privileges_wire((0, 0, 0, [0]*3, []))
    arrays = [[tuple(1000*period+100*index+10+measure for measure in range(6))
               for index in range(count)] for period, count in enumerate((6, 9))]
    parent[chapter_key(13)] = statistics_wire((*arrays, [(0,)*8]*3, []))
    parent[chapter_key(5)] = b'\0\1'+bytes(32)+bytes(2)
    assert parent == captured, 'independent original-map reconstruction'
    assert checkpoint(list(parent.items())).hex() == fixture['parent_checkpoint']
    return parent


def evidence(parent):
    """Independently sign eligible bad-report evidence and check its original C5/roster preconditions."""
    offender, signature = openssl_sign(bytes([16])+bytes(31), b'jam_guarantee'+bytes(32))
    assert parent[chapter_key(5)] == b'\0\1'+bytes(32)+bytes(2)
    assert offender in [row[32:64] for row in roster(parent[chapter_key(8)])]
    assert offender in [row[32:64] for row in roster(parent[chapter_key(9)])]
    return b'\0\1'+bytes(32)+offender+signature+b'\0', offender


def expected_observations(check_frozen=True):
    """Calculate complete expected maps before native execution; observations never seed later parents."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['slots'] == list(SLOTS)
    provider = validate_provider()
    parent = original(fixture)
    dispute, offender = evidence(parent)
    roots = dict(staging=bytes.fromhex(fixture['filtered_staging_ring_root']))
    lines, hashes, commitments = ['P '+fixture['parent_checkpoint']], [], []
    # Only the first child introduces evidence; later crossings consume the cumulative offender set.
    for slot in SLOTS:
        child, parent = successor(parent, slot, [], [], roots, cores=3,
                                  dispute_wire=dispute if slot == 2 else bytes(3),
                                  new_offenders=[offender] if slot == 2 else [])
        encoded = checkpoint(list(parent.items()))
        hashes.append(hashlib.sha256(encoded).hexdigest())
        commitments.append(tree(list(parent.items()))[0].hex())
        lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
    # Explicit generation freezes calculated expectations; normal verification requires every hash.
    if check_frozen:
        assert hashes == fixture['successor_checkpoint_sha256']
        assert commitments == fixture['successor_roots']
    return lines, dict(transitions=len(SLOTS), roots=commitments, checkpoint_sha256=hashes,
                      reference='OpenSSL Ed25519, mathematical Thin and independent whole-map STF',
                      ed25519_provider=provider)
