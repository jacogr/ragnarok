# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map top-twelve contest eviction, winner markers and selected ticket sealing."""
import hashlib
import json
from pathlib import Path
from current_stf_epoch_oracle import (FIXTURE as EPOCH_FIXTURE, bank_records, consensus,
                                      successor, validate_parent)
from current_stf_oracle import decode_checkpoint, checkpoint, tree
from bandersnatch_thin_oracle import sign
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/current-stf-eviction.json'
SLOTS = (2, 3, 4, 5, 6, 7, 10, 11, 12, 13)


def inputs(fixture):
    """Preserve the earlier fourteen immutable inputs and attribute two extra native Ring witnesses mathematically."""
    assert hashlib.sha256(EPOCH_FIXTURE.read_bytes()).hexdigest() == fixture['epoch_fixture_sha256']
    prior = json.loads(EPOCH_FIXTURE.read_text())
    bank = bank_records(prior)+fixture['extra_tickets']
    assert [(item['secret'], item['attempt']) for item in bank[14:]] == [(1, 3), (6, 3)]
    # Ring membership witnesses are fixed; independent O/output prevents changing their scalar attribution.
    for item in bank[14:]:
        proof, score = sign(item['secret'], b'jam_ticket_seal'+bytes(32)+b'\3', b'')
        ring = bytes.fromhex(item['proof'])
        assert len(ring) == 784 and ring[:32] == proof[:32]
        assert item['ring'] == 'pending' and score.hex() == item['score']
    assert bank[14]['score'] < bank[0]['score'] < bank[11]['score'] < bank[15]['score']
    return prior, bank


def expected_observations(check_frozen=True):
    """Calculate every submitted body, Thin credential and whole posterior map without native STF observations."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['slots'] == list(SLOTS)
    prior, bank = inputs(fixture)
    parent = decode_checkpoint(bytes.fromhex(prior['parent_checkpoint']))
    validate_parent(parent)
    roots = dict(pending=consensus(parent[chapter_key(4)])[1],
                 staging=bytes.fromhex(prior['staging_ring_root']))
    lines, hashes, commitments = ['P '+prior['parent_checkpoint']], [], []
    # Fill the old contest before the single improving submission; crossing has no new admission.
    for slot in SLOTS:
        submitted = bank[(slot-2)*3:(slot-1)*3] if 2 <= slot <= 5 else [bank[14]] if slot == 6 else []
        child, parent = successor(parent, slot, submitted, bank, roots)
        encoded = checkpoint(list(parent.items()))
        hashes.append(hashlib.sha256(encoded).hexdigest())
        commitments.append(tree(list(parent.items()))[0].hex())
        lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
    # Ordinary corpus execution requires all independently frozen roots and complete-map hashes.
    if check_frozen:
        assert hashes == fixture['successor_checkpoint_sha256']
        assert commitments == fixture['successor_roots']
    requests = [f"{item['secret']} {item['attempt']} {item['proof']}" for item in bank]
    return requests, lines, dict(transitions=len(SLOTS), roots=commitments, checkpoint_sha256=hashes,
                                 proof_inputs=len(bank), reference='mathematical Thin and independent whole-map STF; fixed Ring/KZG inputs')
