# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-profile ticket admission and complete STF maps over attributed RingVRF inputs."""
from functools import cache
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as guests
from current_stf_oracle import Reader, checkpoint, history, sign, tree
from header_oracle import wire as header_wire
from state_layout_oracle import chapter_key, digest
from state_consensus_oracle import wire as consensus_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-tickets.json'
INPUT = Path(__file__).parent/'fixtures/jam-full-ticket-input.json'


def consensus(data):
    """Decode all pending records, the full600-slot schedule and strictly ordered accumulator."""
    source = Reader(data); count = source.count()
    assert 1 <= count <= 1023
    pending = [source.take(336) for _ in range(count)]; root = source.take(144)
    kind = source.take(1)[0]; assert kind in (0,1)
    schedule = [source.take(32 if kind else 33) for _ in range(600)]
    tickets = [source.take(33) for _ in range(source.count())]; source.done()
    assert len(tickets) <= 600 and all(a[:32] < b[:32] for a,b in zip(tickets,tickets[1:]))
    return pending,root,kind,schedule,tickets


@cache
def bank():
    """Validate attributed membership inputs against independent Thin output/context and the existing ring witness."""
    value = json.loads(INPUT.read_text()); records = guests.roster_records()
    assert value['graypaper_commit'] == full.GP and value['capacity'] == 1023
    assert value['bandersnatch_pins_sha256'] == hashlib.sha256(Path('spec/bandersnatch-pins.json').read_bytes()).hexdigest()
    assert value['members_sha256'] == hashlib.sha256(b''.join(row[:32] for row in records)).hexdigest()
    assert value['commitment'] == json.loads(guests.RING.read_text())['commitment']
    rows = value['tickets']
    # Ring/KZG proofs are attributed input only; scores and O points are recalculated mathematically.
    for row in rows:
        assert 1 <= row['secret'] <= 1023 and row['attempt'] in (0,1)
        proof,score = sign(row['secret'],b'jam_ticket_seal'+bytes(32)+bytes([row['attempt']]),b'')
        assert len(bytes.fromhex(row['proof'])) == 784 and bytes.fromhex(row['proof'])[:32] == proof[:32]
        assert row['score'] == score.hex()
    assert len({(row['secret'],row['attempt']) for row in rows}) == len(rows) == 20
    return tuple(sorted(rows,key=lambda row:row['score']))


def tickets_wire(submitted):
    """Canonical full16-entry submissions retain each frozen attempt and exact membership proof."""
    return natural(len(submitted))+b''.join(bytes([row['attempt']])+bytes.fromhex(row['proof']) for row in submitted)


def successor(parent,slot,submitted):
    """Apply same-epoch ticket union/truncation, authentic fallback sealing and every complete posterior chapter."""
    previous = int.from_bytes(parent[chapter_key(11)],'little')
    assert previous < slot and previous//600 == slot//600
    pending,root,kind,schedule,accumulated = consensus(parent[chapter_key(4)])
    assert kind == 1 and len(submitted) <= 16 and (not submitted or slot % 600 < 500), 'ticket window'
    entropy = parent[chapter_key(6)]; incoming = []
    # A proof's score is independently derived; the membership witness must use exactly posterior eta2.
    for row in submitted:
        assert 0 <= row['attempt'] < (1200+len(pending)-1)//len(pending), 'attempt domain'
        proof,score = sign(row['secret'],b'jam_ticket_seal'+entropy[64:96]+bytes([row['attempt']]),b'')
        assert bytes.fromhex(row['proof'])[:32] == proof[:32], 'proof context'
        assert all(score != old[:32] for old in accumulated), 'duplicate ticket'
        incoming.append(score+bytes([row['attempt']]))
    assert all(a[:32] < b[:32] for a,b in zip(incoming,incoming[1:])), 'ticket order'
    retained = sorted(accumulated+incoming,key=lambda row:row[:32])[:600]
    assert all(row in retained for row in incoming), 'ticket not retained'
    wire,entropy_output,author = sealed(parent,slot,submitted)
    header = wire[:-len(tickets_wire(submitted)+bytes(6))]
    result = full.successor(parent,header,entropy_output,author=author)
    result[chapter_key(4)] = consensus_wire((b''.join(pending),root,kind,b''.join(schedule),b''.join(retained)))
    stats,_ = statistics_parse(result[chapter_key(13)],(341,1023,1023,2**64-1,2**64-1))
    current,previous_stats,cores,services = stats
    counters = list(current[author]); counters[1] += len(submitted); current[author] = tuple(counters)
    result[chapter_key(13)] = statistics_wire((current,previous_stats,cores,services))
    return wire,result


def sealed(parent,slot,submitted):
    """Author exact signed body bytes even for a deliberately inadmissible ticket batch, never a hypothetical successor."""
    _,_,kind,schedule,_ = consensus(parent[chapter_key(4)])
    assert kind == 1
    entropy = parent[chapter_key(6)]
    active = guests.roster_records(); selected = schedule[slot % 600]
    author = next(index for index,row in enumerate(active) if row[:32] == selected)
    secret = author+1; context = b'jam_fallback_seal'+entropy[96:128]
    _,output = sign(secret,context,b''); proof,entropy_output = sign(secret,b'jam_entropy'+output,b'')
    tickets = tickets_wire(submitted); body = tickets+bytes(6)
    commitment = digest(digest(tickets)+3*digest(b'\0')+digest(bytes(3)))
    value = dict(parent=history(parent[chapter_key(3)])[0][-1][0][:32],parent_state_root=tree(list(parent.items()))[0],
                 extrinsic_hash=commitment,slot=slot,epoch_mark=None,tickets_mark=None,author_index=author,
                 entropy_source=proof,offenders_mark=[])
    value['seal'],_ = sign(secret,context,header_wire('U',value)); header = header_wire('H',value)
    return header+body,entropy_output,author


def expected_observations(check_frozen=True):
    """Freeze maximal, singleton and empty admission paths before any native STF or upstream process executes."""
    lines,roots,hashes = [],[],[]; inputs = bank()
    # Distinct partitions exercise a full16-ticket block and both legal attempt values without reusing a score.
    for batches in ((inputs[:16],inputs[16:],()),(inputs[:1],inputs[1:17],inputs[17:])):
        parent = guests.original('create');lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]);hashes.append([])
        for slot,submitted in enumerate(batches,2):
            wire,parent = successor(parent,slot,submitted); encoded = checkpoint(list(parent.items()))
            lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=full.GP,chains=2,transitions=6,submitted_per_chain=20,
                    ticket_input_sha256=hashlib.sha256(INPUT.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    # Fixed complete-map pins are compared before invoking a client; native output cannot repair expectations.
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
