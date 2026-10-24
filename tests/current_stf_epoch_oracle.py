# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map epoch rotation, contest, marker and ticket/fallback sealing equations.

The frozen RingVRF membership proofs and ring commitments are attributed native input witnesses,
not an independent ring-proof/KZG implementation. Ticket O/output and every Thin credential use
the mathematical reference; all successor entries are calculated without native STF observations.
"""
from pathlib import Path
import hashlib
import json
from current_stf_oracle import (Reader, decode_checkpoint, history, advance_chapters, checkpoint, tree)
from bandersnatch_thin_oracle import sign
from test_bandersnatch_thin_reference import G, multiply, encode
from state_layout_oracle import chapter_key, chapter_service, digest
from state_consensus_oracle import wire as consensus_wire
from header_oracle import wire as header_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-epoch.json'
SLOTS = ((2, 3, 4, 5, 10, 11, 12, 13, 36, 37), (2, 3, 4, 5, 12, 13), (2, 3, 10, 11, 12, 13))
NAMES = ('saturated-tail', 'skipped-tail', 'incomplete-tail')
PUBLIC = {encode(multiply(G, secret)): secret for secret in range(1, 10)}
NULL_VALIDATOR = bytes(32)+b'\2'+bytes(303)


def roster(data):
    """Decode six/nine opaque validator records without dropping Ed/BLS/metadata bytes."""
    source = Reader(data)
    count = source.count()
    assert count in (6, 9)
    records = [source.take(336) for _ in range(count)]
    source.done()
    return records


def consensus(data):
    """Decode the complete C4 tuple and retain every schedule/attempt byte."""
    source = Reader(data)
    count = source.count()
    assert count in (6, 9)
    pending = [source.take(336) for _ in range(count)]
    root = source.take(144)
    kind = source.take(1)[0]
    assert kind in (0, 1)
    schedule = [source.take(33 if kind == 0 else 32) for _ in range(12)]
    accumulated = [source.take(33) for _ in range(source.count())]
    source.done()
    assert len(accumulated) <= 12 and all(a[:32] < b[:32] for a, b in zip(accumulated, accumulated[1:]))
    return pending, root, kind, schedule, accumulated


def zigzag(values):
    """Outside-in winner permutation preserves both identifier and entry-index bytes."""
    assert len(values) == 12
    return [values[index//2 if index % 2 == 0 else 11-index//2] for index in range(12)]


def bank_records(fixture):
    """Attribute fixed ring inputs to independently calculated ticket O/output under the zero historical seed."""
    bank = fixture['ticket_bank']
    assert len(bank) == 14
    for index, item in enumerate(bank):
        assert 1 <= item['secret'] <= 6 and 0 <= item['attempt'] < 4
        transcript = b'jam_ticket_seal'+bytes(32)+bytes([item['attempt']])
        proof, score = sign(item['secret'], transcript, b'')
        ring = bytes.fromhex(item['proof'])
        assert len(ring) == 784 and ring[:32] == proof[:32]
        assert item['score'] == score.hex()
        assert item['ring'] == ('pending' if index < 12 else 'staging')
    assert [item['score'] for item in bank[:12]] == sorted(set(item['score'] for item in bank[:12]))
    assert {(item['secret'], item['attempt']) for item in bank[:12]} == {
        (secret, attempt) for secret in range(1, 7) for attempt in range(2)}
    assert [(item['secret'], item['attempt']) for item in bank[12:]] == [(1, 2), (2, 3)]
    return bank


def validate_parent(parent):
    """Distinct known keys and different original roster orders make every epoch role observable."""
    active = roster(parent[chapter_key(8)])
    pending, _, kind, schedule, accumulated = consensus(parent[chapter_key(4)])
    assert [PUBLIC[record[:32]] for record in active] == list(range(1, 7))
    assert pending == active[1:]+active[:1]
    assert roster(parent[chapter_key(7)]) == list(reversed(active))
    assert roster(parent[chapter_key(9)]) == active[2:]+active[:2]
    assert kind == 1 and schedule == [active[i % 6][:32] for i in range(12)] and not accumulated
    assert parent[chapter_key(6)] == bytes(128) and parent[chapter_key(11)] == (1).to_bytes(4, 'little')
    assert len(parent) == 30 and {chapter_key(i) for i in range(1, 17)} <= parent.keys()
    assert all(len(parent[chapter_service(255, sid)]) == 105 for sid in (42, 99))
    assert all(parent[chapter_key(i)] == bytes(length) for i, length in ((10, 2), (14, 12), (15, 12)))


def submitted_for(slot, bank):
    """All three paths use the same declared ticket batches; incomplete mode simply never visits slots4/5."""
    if 2 <= slot <= 5:
        return bank[(slot-2)*3:(slot-1)*3]
    if slot in (12, 13):
        return [bank[12 if slot == 12 else 13]]
    return []


def successor(parent, slot, submitted, bank, roots, *, cores=2, dispute_wire=bytes(3),
              new_offenders=(), body_override=None, extrinsic_override=None, outputs=()):
    """Calculate each header, admitted contest, rotated state and entire successor independently."""
    previous = int.from_bytes(parent[chapter_key(11)], 'little')
    assert slot > previous
    pending, root, kind, schedule, accumulated = consensus(parent[chapter_key(4)])
    active = roster(parent[chapter_key(8)])
    entropy = [parent[chapter_key(6)][i:i+32] for i in range(0, 128, 32)]
    crossed = slot//12 > previous//12
    judgments = Reader(parent[chapter_key(5)])
    sets = [[judgments.take(32) for _ in range(judgments.count())] for _ in range(4)]
    judgments.done()
    assert all(len(key) == 32 for key in new_offenders)  # Header sequence preserves cross-section repeats.
    offenders = sorted(set(sets[3]) | set(new_offenders))
    post_pending = [NULL_VALIDATOR if row[32:64] in offenders else row
                    for row in roster(parent[chapter_key(7)])] if crossed else pending
    post_active = pending if crossed else active
    post_root = roots['staging'] if crossed else root
    # Current entropy[2] after a crossing is old eta1; the contest never uses freshly derived entropy.
    seed = entropy[1 if crossed else 2]
    assert len(submitted) <= 3 and (not submitted or slot % 12 < 10), 'ticket window'
    incoming = []
    for item in submitted:
        assert 0 <= item['attempt'] < (24+len(post_pending)-1)//len(post_pending), 'attempt domain'
        assert roots[item['ring']] == post_root, 'ring domain'
        proof, score = sign(item['secret'], b'jam_ticket_seal'+seed+bytes([item['attempt']]), b'')
        assert bytes.fromhex(item['proof'])[:32] == proof[:32], 'ticket O/context'
        ticket = score+bytes([item['attempt']])
        assert all(ticket[:32] != old[:32] for old in accumulated), 'duplicate ticket'
        incoming.append(ticket)
    assert all(a[:32] < b[:32] for a, b in zip(incoming, incoming[1:])), 'ticket order'
    kept = sorted(([] if crossed else accumulated)+incoming, key=lambda item: item[:32])[:12]
    assert all(item in kept for item in incoming), 'ticket not retained'
    if crossed:
        if slot//12 == previous//12+1 and previous % 12 >= 10 and len(accumulated) == 12:
            post_kind, post_schedule = 0, zigzag(accumulated)
        else:
            post_kind = 1
            post_schedule = [post_active[int.from_bytes(digest(seed+i.to_bytes(4, 'little'))[:4],
                                                        'little') % len(post_active)][:32] for i in range(12)]
    else:
        post_kind, post_schedule = kind, schedule
    epoch = None
    if crossed:
        epoch = dict(entropy=entropy[0], tickets_entropy=entropy[1], validators=[
            dict(bandersnatch=row[:32], ed25519=row[32:64]) for row in post_pending])
    winners = None
    if not crossed and previous % 12 < 10 <= slot % 12 and len(accumulated) == 12:
        winners = [dict(id=item[:32], attempt=item[32]) for item in zigzag(accumulated)]
    selected = post_schedule[slot % 12]
    if post_kind == 0:
        attributed = [item for item in bank if bytes.fromhex(item['score']) == selected[:32]]
        assert len(attributed) == 1 and attributed[0]['attempt'] == selected[32]
        secret = attributed[0]['secret']
        transcript = b'jam_ticket_seal'+entropy[2 if crossed else 3]+selected[32:]
    else:
        secret = PUBLIC[selected]
        transcript = b'jam_fallback_seal'+entropy[2 if crossed else 3]
    author = next(i for i, record in enumerate(post_active) if PUBLIC.get(record[:32]) == secret)
    _, seal_output = sign(secret, transcript, b'')
    if post_kind == 0:
        assert seal_output == selected[:32]
    entropy_proof, entropy_output = sign(secret, b'jam_entropy'+seal_output, b'')
    tickets = natural(len(submitted))+b''.join(bytes([item['attempt']])+bytes.fromhex(item['proof'])
                                              for item in submitted)
    body = tickets+bytes(3)+dispute_wire
    commitment = digest(digest(tickets)+3*digest(b'\0')+digest(dispute_wire))
    if body_override is not None:
        assert not submitted and extrinsic_override is not None
        body, commitment = body_override, extrinsic_override
    blocks, _ = history(parent[chapter_key(3)])
    source = dict(parent=blocks[-1][0][:32], parent_state_root=tree(list(parent.items()))[0],
                  extrinsic_hash=commitment, slot=slot, epoch_mark=epoch, tickets_mark=winners,
                  author_index=author, entropy_source=entropy_proof, offenders_mark=list(new_offenders))
    source['seal'], _ = sign(secret, transcript, header_wire('U', source))
    header = header_wire('H', source)
    result = advance_chapters(parent, header, slot, author, entropy_output,
                              ticket_count=len(submitted), cores=cores, outputs=outputs)
    result[chapter_key(4)] = consensus_wire((b''.join(post_pending), post_root, post_kind,
                                            b''.join(post_schedule), b''.join(kept)))
    if crossed:
        result[chapter_key(8)] = natural(len(post_active))+b''.join(post_active)
        result[chapter_key(9)] = parent[chapter_key(8)]
    if new_offenders:
        result[chapter_key(5)] = b''.join(natural(len(values))+b''.join(values)
                                         for values in (*sets[:3], offenders))
    return header+body, result


def expected_observations():
    """Return fixed proof input requests and every independently calculated expected wire before native execution."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    bank = bank_records(fixture)
    original = bytes.fromhex(fixture['parent_checkpoint'])
    parent = decode_checkpoint(original)
    validate_parent(parent)
    roots = dict(pending=consensus(parent[chapter_key(4)])[1], staging=bytes.fromhex(fixture['staging_ring_root']))
    requests = [f"{item['secret']} {item['attempt']} {item['proof']}" for item in bank]
    lines, all_roots = [], []
    assert [case['name'] for case in fixture['cases']] == list(NAMES)
    for case, slots in zip(fixture['cases'], SLOTS):
        expected = dict(parent)
        lines.append('P '+original.hex())
        assert len(case['successor_roots']) == len(case['successor_checkpoint_sha256']) == len(slots)
        current_roots = []
        for index, slot in enumerate(slots):
            child, expected = successor(expected, slot, submitted_for(slot, bank), bank, roots)
            encoded = checkpoint(list(expected.items()))
            root = tree(list(expected.items()))[0].hex()
            assert root == case['successor_roots'][index]
            assert hashlib.sha256(encoded).hexdigest() == case['successor_checkpoint_sha256'][index]
            current_roots.append(root)
            lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
        all_roots.append(current_roots)
    evidence = dict(transitions=sum(map(len, SLOTS)), chains=3, roots=all_roots,
                    proof_inputs=14, reference='independent Thin O/output and STF; fixed native Ring/KZG inputs')
    return requests, lines, evidence
