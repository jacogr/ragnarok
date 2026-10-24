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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-foreign-creation.json'
PROFILES = ('liquid-liquid','protected-liquid','liquid-protected','protected-protected','stale-supervisor','panic','checkpoint-panic')
PAYLOAD = b'R'


from current_stf_service_upgrades_oracle import replacement
from current_stf_reserved_creation_oracle import minimum
from state_privileges_oracle import wire as privileges_wire


def junior_program():
    """The simultaneously participating funded account writes only its own one-byte raw storage entry."""
    instructions=[immediate(7,2**64-1),immediate(8,196608),immediate(9,1),immediate(10,196609),immediate(11,1),bytes([10,5]),bytes([50,0])]
    return instructions,bytes([7,42])


def program(profile):
    """The registrar funds reserved77 from the genuine supervised42 account, selecting exactly one source/destination pool."""
    target=replacement();memory=digest(target)+len(target).to_bytes(4,'little')+(100).to_bytes(8,'little')+(19).to_bytes(8,'little')+bytes(8)
    pool=PROFILES.index(profile) if profile in PROFILES[:4] else 0
    instructions=[immediate(7,42),immediate(8,77),immediate(9,pool),immediate(10,196608),bytes([10,20])]
    if profile=='checkpoint-panic':
        instructions.append(bytes([10,19])) # Capture the foreign debit and child credit together before panic.
    instructions.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    return instructions,memory


def original(profile):
    """Both originals are funded under7/1/100 deposits; only42 owns the selected million-token source pool."""
    parent=transfers.original('halt')
    for sid,(instructions,memory) in ((42,junior_program()),(99,program(profile))):
        key=chapter_service(255,sid);old_hash,wide,narrow=account_parse(parent[key],105)
        old=parent.pop(value_key('P',sid,old_hash));del parent[request_key(sid,old_hash,len(old))]
        raw=envelope(instructions,memory);hashed=digest(raw);parent[value_key('P',sid,hashed)]=raw
        parent[request_key(sid,hashed,len(raw))]=request_wire((1,));wide,narrow=list(wide),list(narrow);wide[4]+=len(raw)-len(old)
        if sid==42:
            protected=profile in ('protected-liquid','protected-protected');wide[0]=0 if protected else 1000000;wide[1]=1000000 if protected else 0
            narrow[4]=99;narrow[5]=int(profile=='stale-supervisor') # Only the actual matching99 incarnation authorizes foreign funding.
        else:
            wide[0]=10000 # The registrar is funded but cannot silently substitute its own pool for42's.
        parent[key]=account_wire((hashed,wide,narrow))
    parent[chapter_key(12)]=privileges_wire((0,0,99,[0,0],[]));return parent


def effects(result,parent,profile,slot,budget):
    """N annuls the junior write only when a selected first foreign debit modifies42; M then publishes that exact funded snapshot."""
    child=chapter_service(255,77);born=profile not in ('stale-supervisor','panic') and child not in parent
    selection=PROFILES.index(profile) if profile in PROFILES[:4] else 0
    key=chapter_service(255,42);code,wide,narrow=account_parse(parent[key],105);wide,narrow=list(wide),list(narrow)
    if born:
        wide[1 if selection in (1,3) else 0]-=224
        pools=(224,0) if selection in (0,1) else (0,224)
        result[child]=account_wire((digest(replacement()),(*pools,100,19,110,0),(2,slot,0,99,99,0)))
        result[request_key(77,digest(replacement()),len(replacement()))]=request_wire(())
    else:
        storage=value_key('S',42,b'\7')
        if storage not in parent:
            wide[4]+=36;narrow[0]+=1 # A later FULL returns before mutation, so the previously annulled own write now survives.
        result[storage]=bytes([42])
    narrow[2]=slot;result[key]=account_wire((code,wide,narrow));assert sum(wide[:2])>=minimum((code,wide,narrow))
    key=chapter_service(255,99);code,wide,narrow=account_parse(parent[key],105);narrow=list(narrow);narrow[2]=slot;result[key]=account_wire((code,wide,narrow))
    first,_=junior_program();second,_=program(profile)
    gas42=simulate(first,gas_definitions(),prefix=[b'\0']*5)[0]+2442+(3358+1023)//1024+(216+1023)//1024
    gas99=simulate(second,gas_definitions(),prefix=[b'\0']*5)[0]+3855+103*int(profile=='checkpoint-panic');assert max(gas42,gas99)<=budget
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT);activity={row[0]:list(row) for row in services}
    for sid,gas in ((42,gas42),(99,gas99)):
        row=activity.setdefault(sid,[sid]+[0]*11);row[9]+=1;row[11]+=gas # Annulment does not erase the junior's actual operand or gas.
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,created=born,junior_write_retained=not born,gas42=gas42,gas99=gas99)


def expected_observations(check_frozen=True):
    """Calculate forty-two full transitions with foreign funding, common-prior conflict selection and repeated reserved-ID admission."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+176)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 8):
            budget = 100000
            gs = [pipeline.guarantee(parent,initial,core,slot,service=sid,accumulation_gas=budget) for core,sid in ((0,42),(1,99))] if slot in (3,5) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent,5 if slot in (4,6) else 0,3)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4, 6) else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released) == 2
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
    return requests, lines, dict(transitions=42, chains=7, roots=roots, checkpoint_sha256=hashes, traces=traces)
