# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full600-ticket contest eviction, all-or-nothing non-retention and unchanged-map refusals."""
from functools import cache
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_tickets_oracle as tickets
import jam_fuzzer_full_guests_oracle as guests
from current_stf_oracle import checkpoint, sign, tree
from state_layout_oracle import chapter_key
from state_consensus_oracle import wire as consensus_wire

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-contest.json'


@cache
def contest():
    """Every seeded ticket is a mathematical output of a distinct known member of the unchanged1023-member ring."""
    result = []
    # These members are disjoint from the frozen incoming proof bank; no accumulator entry is invented from random bytes.
    for secret in range(17,1024):
        _,score = sign(secret,b'jam_ticket_seal'+bytes(33),b'')
        result.append(score+b'\0')
    result.sort(key=lambda row:row[:32])
    assert len({row[:32] for row in result}) == 1007
    return tuple(result[:600])


def original(size):
    """Author a supplied complete checkpoint with a canonical599/600-ticket contest before replay starts."""
    assert size in (599,600)
    parent = guests.original('create')
    pending,root,kind,schedule,_ = tickets.consensus(parent[chapter_key(4)])
    parent[chapter_key(4)] = consensus_wire((b''.join(pending),root,kind,b''.join(schedule),b''.join(contest()[:size])))
    return parent


def expected_observations(check_frozen=True):
    """Freeze exact eviction maps and signed high-score/mixed/duplicate refusals before consulting any native result."""
    bank = tickets.bank(); boundary = contest()[-1][:32]
    low = [row for row in bank if bytes.fromhex(row['score']) < boundary]
    high = [row for row in bank if bytes.fromhex(row['score']) > boundary]
    assert len(low) >= 2 and high
    plans = ((600,(('R',2,[high[-1]],'NotRetained'),('B',2,[low[0]],None),
                   ('R',3,[low[0]],'Duplicate'),('R',3,[low[1],high[-1]],'NotRetained'),
                   ('B',3,[low[1]],None),('B',4,[],None))),
             (599,(('B',2,[low[0]],None),('R',3,[high[-1]],'NotRetained'),('B',3,[low[1]],None))))
    lines,roots,hashes = [],[],[]
    # A refused batch must keep even an otherwise-retainable prefix out of the complete accumulator and statistics.
    for size,steps in plans:
        parent = original(size);lines.append('P '+checkpoint(list(parent.items())).hex());roots.append([]);hashes.append([])
        for kind,slot,submitted,reason in steps:
            if kind == 'R':
                expected = 'duplicate ticket' if reason == 'Duplicate' else 'ticket not retained'
                try: tickets.successor(parent,slot,submitted)
                except AssertionError as error: assert str(error) == expected
                else: raise AssertionError('independent reference admitted a refused ticket batch')
                wire,_,_ = tickets.sealed(parent,slot,submitted)
                lines.append('R '+wire.hex()+' ticket/'+reason)
            else:
                before = tickets.consensus(parent[chapter_key(4)])[4]
                wire,parent = tickets.successor(parent,slot,submitted);lines.append('B '+wire.hex())
                after = tickets.consensus(parent[chapter_key(4)])[4]
                assert len(after) == 600 and all(bytes.fromhex(row['score']) in [value[:32] for value in after] for row in submitted)
                # A saturated update replaces exactly one old worst entry; an empty block leaves the contest unchanged.
                if len(before) == 600 and submitted: assert len(set(before)-set(after)) == len(submitted)
                elif not submitted: assert before == after
            encoded = checkpoint(list(parent.items()));lines.append('O '+encoded.hex())
            roots[-1].append(tree(list(parent.items()))[0].hex());hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=tickets.full.GP,chains=2,transitions=9,accepted=5,refused=4,
                    initial_contest_sha256=hashlib.sha256(b''.join(contest())).hexdigest(),
                    ticket_input_sha256=hashlib.sha256(tickets.INPUT.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    # Refusal maps are exact copies of independent prior maps, never observations of a failed client call.
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
