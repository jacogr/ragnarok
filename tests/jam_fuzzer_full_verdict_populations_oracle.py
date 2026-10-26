# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent parent-selected683/681 verdict quorums, NULL positions, previous-only evidence and membership expiry."""
import copy
import hashlib
import json
from pathlib import Path
import jam_fuzzer_full_population_oracle as population
import jam_fuzzer_full_verdicts_oracle as verdicts
import jam_fuzzer_full_offenders_oracle as offenders
import jam_fuzzer_full_profile_oracle as full
import jam_fuzzer_full_guests_oracle as guests
from current_stf_oracle import checkpoint,tree
from state_layout_oracle import chapter_key,digest
from disputes_oracle import wire as disputes_wire

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-full-verdict-populations.json'
TARGETS = {name:digest(('full verdict population '+name).encode()) for name in ('boundary','current','previous','good')}


def advance(parent,slot,value):
    """Classify against original parent populations, then independently rotate with posterior judgments and exact evidence marks."""
    assert parent[chapter_key(10)] == bytes(341)
    after,marks,_ = verdicts.plan(parent,value)
    return population.successor(parent,slot,disputes=disputes_wire(value),marks=marks,posterior_judgments=after)


def refused(parent,slot,value,reason):
    """Seal one independently invalid verdict/evidence body without constructing any hypothetical accepted state."""
    try: verdicts.plan(parent,value)
    except AssertionError as error: assert str(error) == reason
    else: raise AssertionError('independent reference admitted invalid population-selected evidence')
    marks = [row['key'] for section in ('culprits','faults') for row in value[section]]
    wire,_ = population.successor(parent,slot,disputes=disputes_wire(value),marks=marks)
    return wire


def expected_observations(check_frozen=True):
    """Freeze complete actual population prefixes, parent-before-rotation verdicts and previous-roster evidence lifetime."""
    parent = population.original();states = []
    # Preserve all original good/bad records and establish actual Phi before the first1020-pending transition.
    for wire,parent in population.prelude(parent): states.append(('B',wire,parent,None))
    for slot in (599,600,601,1199):
        wire,parent = population.successor(parent,slot);states.append(('B',wire,parent,None))
    boundary = verdicts.verdict(parent,TARGETS['boundary'],1,0)
    assert len(boundary['votes']) == 683 and boundary['votes'][-1]['index'] == 1022
    wrong = verdicts.payload([verdicts.verdict(parent,TARGETS['boundary'],1,0,count=681)])
    states.append(('R',refused(parent,1200,wrong,'InvalidQuorum'),parent,'InvalidQuorum'))
    wire,parent = advance(parent,1200,verdicts.payload([boundary]));states.append(('B',wire,parent,None))
    current = verdicts.verdict(parent,TARGETS['current'],2,0)
    previous = verdicts.verdict(parent,TARGETS['previous'],1,341)
    assert len(current['votes']) == 681 and len(previous['votes']) == 683
    assert current['votes'][-1]['index'] == 1018 and previous['votes'][-1]['index'] == 1022
    # Physical NULL slots still count toward the selected population; fewer usable secrets do not lower the GP quorum.
    members = offenders.roster(parent[chapter_key(8)]);usable = sum(row[32:64] in offenders.identities() for row in members)
    assert len(members) == 1020 and usable == 1016
    nonnull_quorum = 2*(usable//3)+1
    wrong_current = verdicts.payload([verdicts.verdict(parent,TARGETS['current'],2,0,count=nonnull_quorum)])
    wrong_previous = verdicts.payload([verdicts.verdict(parent,TARGETS['previous'],1,341,count=681)])
    valid = verdicts.payload([current,previous]);signature = copy.deepcopy(valid)
    item = next(row for row in signature['verdicts'] if row['target'] == TARGETS['previous'])
    old = item['votes'][0];wrong_owner = offenders.identities()[members[old['index']][32:64]]
    item['votes'][0] = verdicts.vote(wrong_owner,old['index'],old['vote'],item['target'])
    for value,reason in ((wrong_current,'InvalidQuorum'),(wrong_previous,'InvalidQuorum'),(signature,'InvalidSignature')):
        states.append(('R',refused(parent,1201,value,reason),parent,reason))
    wire,parent = advance(parent,1201,valid);states.append(('B',wire,parent,None))
    good = verdicts.verdict(parent,TARGETS['good'],2,681)
    previous_key = guests.roster_records()[1020][32:64]
    assert previous_key not in {row[32:64] for row in offenders.roster(parent[chapter_key(8)])}
    assert previous_key in {row[32:64] for row in offenders.roster(parent[chapter_key(9)])}
    value = verdicts.payload([good],faults=[offenders.fault(1020,TARGETS['good'],False)])
    wire,parent = advance(parent,1202,value);states.append(('B',wire,parent,None))
    for slot in (1203,1800):
        wire,parent = advance(parent,slot,verdicts.payload());states.append(('B',wire,parent,None))
    expired = verdicts.payload(culprits=[offenders.culprit(1021,TARGETS['boundary'])])
    states.append(('R',refused(parent,1801,expired,'InvalidKey'),parent,'InvalidKey'))
    wire,parent = advance(parent,1801,verdicts.payload());states.append(('B',wire,parent,None))
    assert [len(group) for group in offenders.judgments(parent[chapter_key(5)])] == [2,3,1,6]
    assert len(states) == 17 and sum(kind == 'R' for kind,_,_,_ in states) == 5
    lines = ['P '+checkpoint(list(population.original().items())).hex()];roots,hashes = [[]],[[]]
    for kind,wire,state,reason in states:
        lines.append(kind+' '+wire.hex()+(' dispute/'+reason if reason is not None else ''))
        encoded = checkpoint(list(state.items()));lines.append('O '+encoded.hex())
        roots[0].append(tree(list(state.items()))[0].hex());hashes[0].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(graypaper_commit=full.GP,chains=1,transitions=17,accepted=12,refused=5,
                    current_quorum=681,previous_quorum=683,parent_boundary_quorum=683,nonnull_wrong_quorum=nonnull_quorum,
                    population_fixture_sha256=hashlib.sha256(population.FIXTURE.read_bytes()).hexdigest(),
                    verdict_fixture_sha256=hashlib.sha256(verdicts.FIXTURE.read_bytes()).hexdigest(),
                    successor_roots=roots,successor_checkpoint_sha256=hashes,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen: assert json.loads(FIXTURE.read_text()) == evidence
    return [],lines,evidence
