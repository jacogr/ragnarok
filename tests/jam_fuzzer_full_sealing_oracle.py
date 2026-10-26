# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full600-slot winner markers, ticket seals, skipped-tail/epoch fallback and exact marker refusals."""
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_contest_oracle as contest
import jam_fuzzer_full_tickets_oracle as tickets
import jam_fuzzer_full_guests_oracle as guests
import jam_fuzzer_full_profile_oracle as full
from current_stf_oracle import Reader,checkpoint,history,sign,tree
from header_oracle import wire as header_wire
from state_layout_oracle import chapter_key,digest
from state_consensus_oracle import wire as consensus_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-sealing.json'
# Ordinary activation, skipped tail, incomplete contest and multi-epoch skip isolate the GP schedule predicates.
PLANS = ((600,(2,499,500,501,599,600,601,1100,1200,1201)),
         (600,(499,600,601)),(599,(499,500,599,600,601)),(600,(499,500,1200,1201)))


def zigzag(values):
    """The600 winners alternate lowest/highest while preserving the complete33-byte identifier/attempt pairs."""
    assert len(values) == 600
    return [values[index//2 if index % 2 == 0 else 599-index//2] for index in range(600)]


def roster(data):
    """Decode complete fixed1023-member opaque records before any schedule or marker calculation."""
    source = Reader(data);count = source.count();assert count == 1023
    rows = [source.take(336) for _ in range(count)];source.done()
    return rows


def successor(parent,slot,*,marker_fault=None):
    """Derive full ordinary/skipped schedules, Thin ticket/fallback credentials and complete posterior maps independently."""
    previous = int.from_bytes(parent[chapter_key(11)],'little');assert previous < slot
    pending,root,kind,schedule,accumulated = tickets.consensus(parent[chapter_key(4)])
    active = roster(parent[chapter_key(8)]); entropy = parent[chapter_key(6)]
    crossed = slot//600 > previous//600; adjacent = slot//600 == previous//600+1
    epoch = None;winners = None;retained = accumulated
    # GP selects from the prior contest only after an observed prior tail and one adjacent epoch crossing.
    if crossed:
        active,pending = pending,roster(parent[chapter_key(7)])
        assert pending == list(guests.roster_records())
        root = bytes.fromhex(json.loads(guests.RING.read_text())['commitment'])
        seed = entropy[32:64]
        if adjacent and previous % 600 >= 500 and len(accumulated) == 600:
            kind,schedule = 0,zigzag(accumulated)
        else:
            kind = 1
            schedule = [active[int.from_bytes(digest(seed+index.to_bytes(4,'little'))[:4],'little') % len(active)][:32]
                        for index in range(600)]
        epoch = dict(entropy=entropy[:32],tickets_entropy=entropy[32:64],validators=[dict(bandersnatch=row[:32],ed25519=row[32:64]) for row in pending])
        retained = []
    elif previous % 600 < 500 <= slot % 600 and len(accumulated) == 600:
        winners = [dict(id=row[:32],attempt=row[32]) for row in zigzag(accumulated)]
    selected = schedule[slot % 600]
    # Full fixture scalars independently bind each selected credential, including a nontrivial winner index.
    if kind == 0:
        owners = dict(contest.ticket_owners())
        owners.update({bytes.fromhex(row['score']):row['secret'] for row in tickets.bank()})
        secret = owners[selected[:32]]
        context = b'jam_ticket_seal'+entropy[64:96] if crossed else b'jam_ticket_seal'+entropy[96:128]
        context += selected[32:]
    else:
        secret = next(index+1 for index,row in enumerate(guests.roster_records()) if row[:32] == selected)
        context = b'jam_fallback_seal'+(entropy[64:96] if crossed else entropy[96:128])
    public = guests.roster_records()[secret-1][:32]
    author = next(index for index,row in enumerate(active) if row[:32] == public)
    _,output = sign(secret,context,b'')
    if kind == 0: assert output == selected[:32]
    proof,entropy_output = sign(secret,b'jam_entropy'+output,b'')
    value = dict(parent=history(parent[chapter_key(3)])[0][-1][0][:32],parent_state_root=tree(list(parent.items()))[0],
                 extrinsic_hash=digest(4*digest(b'\0')+digest(bytes(3))),slot=slot,epoch_mark=epoch,tickets_mark=winners,
                 author_index=author,entropy_source=proof,offenders_mark=[])
    # Deliberately invalid marker bytes are still genuinely sealed; their hypothetical successor is never used.
    if marker_fault == 'missing-winners':
        assert winners is not None;value['tickets_mark'] = None
    elif marker_fault == 'wrong-winners':
        assert winners is not None;value['tickets_mark'] = [dict(row) for row in winners]
        value['tickets_mark'][-1]['attempt'] ^= 1
    elif marker_fault == 'unexpected-winners':
        assert winners is None;value['tickets_mark'] = [dict(id=row[:32],attempt=row[32]) for row in zigzag(list(contest.contest()))]
    elif marker_fault == 'missing-epoch':
        assert epoch is not None;value['epoch_mark'] = None
    else: assert marker_fault is None
    value['seal'],_ = sign(secret,context,header_wire('U',value));header = header_wire('H',value)
    result = full.successor(parent,header,entropy_output,author=author)
    result[chapter_key(4)] = consensus_wire((b''.join(pending),root,kind,b''.join(schedule),b''.join(retained)))
    if crossed:
        result[chapter_key(8)] = natural(len(active))+b''.join(active)
        result[chapter_key(9)] = parent[chapter_key(8)]
    return header+bytes(7),result


def expected_observations(check_frozen=True):
    """Freeze full winner activation, all fallback predicates and exact signed marker refusals before native execution."""
    lines,roots,hashes = [],[],[];refused = 0
    for index,(size,slots) in enumerate(PLANS):
        parent = contest.original(size);lines.append('P '+checkpoint(list(parent.items())).hex());roots.append([]);hashes.append([])
        for slot in slots:
            # The ordinary path first changes the saturated contest with a genuinely admitted low-score proof.
            if slot == 2:
                boundary = tickets.consensus(parent[chapter_key(4)])[4][-1][:32]
                incoming = next(row for row in tickets.bank() if bytes.fromhex(row['score']) < boundary)
                wire,parent = tickets.successor(parent,slot,[incoming])
            else:
                faults = ('missing-winners','wrong-winners') if index == 0 and slot == 500 else ()
                if index == 0 and slot == 600: faults = ('missing-epoch',)
                if size == 599 and slot == 500: faults = ('unexpected-winners',)
                for fault in faults:
                    invalid,_ = successor(parent,slot,marker_fault=fault)
                    reason = 'InvalidEpochMarker' if fault == 'missing-epoch' else 'InvalidWinnersMarker'
                    encoded = checkpoint(list(parent.items()))
                    lines.extend(('R '+invalid.hex()+' marker/'+reason,'O '+encoded.hex()))
                    roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest());refused += 1
                wire,parent = successor(parent,slot)
            encoded = checkpoint(list(parent.items()));lines.extend(('B '+wire.hex(),'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            kind = tickets.consensus(parent[chapter_key(4)])[2]
            if slot//600 == 1: assert kind == (0 if index == 0 else 1)
    evidence = dict(graypaper_commit=full.GP,chains=len(PLANS),transitions=sum(map(len,roots)),accepted=sum(len(slots) for _,slots in PLANS),refused=refused,
                    contest_fixture_sha256=hashlib.sha256(contest.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
