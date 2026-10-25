# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map reserved-ID creation, explicit deposit funding and all four balance pool modes cases."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_effects_oracle import immediate, envelope, simulate, gas_definitions
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-reserved-creation.json'
PROFILES = ('liquid-liquid','protected-liquid','liquid-protected','protected-protected','panic','checkpoint-panic','occupied-id','insufficient')
PAYLOAD = b'R'


from current_stf_service_upgrades_oracle import replacement
from state_privileges_oracle import wire as privileges_wire


def program(profile):
    """Registrar99 requests a literal reserved77, with real funding mode and complete60-byte new20 input."""
    selection=PROFILES.index(profile) if profile in PROFILES[:4] else 0
    desired=42 if profile=='occupied-id' else 77
    memory=digest(replacement())+len(replacement()).to_bytes(4,'little')+(100).to_bytes(8,'little')+(19).to_bytes(8,'little')+bytes(8)
    instructions=[immediate(7,2**64-1),immediate(8,desired),immediate(9,selection),immediate(10,196608),bytes([10,20])]
    if profile=='checkpoint-panic':
        instructions.append(bytes([10,19])) # Retain the child and matching source debit together.
    instructions.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    return instructions,memory


def minimum(metadata):
    """Independent unbounded deposit equation under the explicitly declared7/item,1/byte,100/account profile."""
    _,wide,narrow=metadata
    return max(0,100+7*narrow[0]+wide[4]-wide[5])


def original(profile):
    """Every original account is funded; the CASH control has exactly one token less than a valid post-debit balance."""
    parent=transfers.original('halt');key=chapter_service(255,99)
    old_hash,wide,narrow=account_parse(parent[key],105)
    old=parent.pop(value_key('P',99,old_hash));del parent[request_key(99,old_hash,len(old))]
    instructions,memory=program(profile);raw=envelope(instructions,memory);hashed=digest(raw)
    parent[value_key('P',99,hashed)]=raw;parent[request_key(99,hashed,len(raw))]=request_wire((1,))
    wide=list(wide);wide[4]+=len(raw)-len(old)
    if profile in ('protected-liquid','protected-protected'):
        wide[0]=0;wide[1]=1000000 # No borrowing from the unselected liquid pool can hide a wrong funding mode.
    if profile=='insufficient':
        wide[0]=minimum((hashed,wide,narrow))+223 # Child threshold224 would leave this creator one token underfunded.
    parent[key]=account_wire((hashed,wide,narrow))
    key=chapter_service(255,42);code,wide,narrow=account_parse(parent[key],105)
    wide=list(wide);wide[0]=10000;parent[key]=account_wire((code,wide,narrow))
    parent[chapter_key(12)]=privileges_wire((0,0,99,[0,0],[]))
    return parent


def effects(result,parent,profile,slot,budget, *, statistics_config=DEFAULT):
    """Selected child funding consumes one explicit source pool and reaches the chosen child pool exactly once."""
    key=chapter_service(255,99);code,wide,narrow=account_parse(parent[key],105)
    wide,narrow=list(wide),list(narrow);narrow[2]=slot
    child=chapter_service(255,77);born=profile not in ('panic','occupied-id','insufficient') and child not in parent
    if born:
        selection=PROFILES.index(profile) if profile in PROFILES[:4] else 0
        liquid=selection in (0,1);source=1 if selection in (1,3) else 0
        cost=100+2*7+81+len(replacement());assert cost==224
        wide[source]-=cost
        result[child]=account_wire((digest(replacement()),(cost if liquid else 0,0 if liquid else cost,100,19,81+len(replacement()),0),(2,slot,0,99,99,0)))
        result[request_key(77,digest(replacement()),len(replacement()))]=request_wire(())
    result[key]=account_wire((code,wide,narrow))
    instructions,_=program(profile);gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+3855+103*int(profile=='checkpoint-panic')
    assert gas<=budget and sum(wide[:2])>=minimum((code,wide,narrow))
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],statistics_config)
    activity={row[0]:list(row) for row in services};row=activity.setdefault(99,[99]+[0]*11);row[9]+=1;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas=gas,created=born,child_present=child in result,source_liquid=wide[0],source_protected=wide[1])


def expected_observations(check_frozen=True):
    """Calculate forty-eight full transitions with real deposits and repeated reserved-ID admission."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+123)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 8):
            budget = 100000
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99, accumulation_gas=budget)] if slot in (3, 5) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot in (4, 6) else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4, 6) else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released) == 1
                traces[-1].append(effects(result, parent, profile, slot, budgets[released[0][:32]]))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
        assert fixture['deposits'] == dict(per_item=7,per_byte=1,per_account=100)
    return requests, lines, dict(transitions=48, chains=8, roots=roots, checkpoint_sha256=hashes, traces=traces)
