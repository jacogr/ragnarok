# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map authorization queues, assigner handoff and checkpoint selection cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-authorization-assign.json'
PROFILES = ('assign', 'panic', 'checkpoint-panic', 'invalid-core', 'invalid-assigner', 'oversized-code')
PAYLOAD = b'R'


from state_privileges_oracle import wire as privileges_wire


def queue():
    """All80 positions have distinct, independently hashed explicit values and retain their positional order."""
    return b''.join(digest(b'authorization queue A'+bytes([index])) for index in range(80))


def program(profile):
    """The second assign attempts to reclaim99 after the first hands core1 to42; failed-domain calls remain invalid."""
    core=2 if profile=='invalid-core' else 1
    nominee=2**32+42 if profile=='invalid-assigner' else 42
    instructions=[immediate(7,core),immediate(8,196608),immediate(9,nominee),bytes([10,17])]
    if profile=='checkpoint-panic':
        instructions.append(bytes([10,19])) # Capture queue and assigner atomically before the later attempt.
    instructions += [immediate(7,core),immediate(8,196608),immediate(9,nominee if profile=='invalid-assigner' else 99),bytes([10,17])]
    instructions.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    return instructions,queue()


def original(profile):
    """Original assigner99 for both cores owns a genuine initial zero authorization queue."""
    parent=transfers.original('halt');key=chapter_service(255,99)
    old_hash,wide,narrow=account_parse(parent[key],105)
    old=parent.pop(value_key('P',99,old_hash));del parent[request_key(99,old_hash,len(old))]
    instructions,memory=program(profile);raw=envelope(instructions,memory);hashed=digest(raw)
    parent[value_key('P',99,hashed)]=raw;parent[request_key(99,hashed,len(raw))]=request_wire((1,))
    wide=list(wide);wide[4]+=len(raw)-len(old);parent[key]=account_wire((hashed,wide,narrow))
    parent[chapter_key(12)]=privileges_wire((0,0,0,[99,99],[]))
    return parent


def effects(result,parent,profile,slot,budget):
    """Original-role publication selects the original assigner's queue even after its host call hands off authority."""
    retained=profile in ('assign','checkpoint-panic')
    if retained:
        result[chapter_key(2)]=parent[chapter_key(2)][:2560]+queue()
        result[chapter_key(12)]=privileges_wire((0,0,0,[99,42],[])) # The second host call cannot reclaim this role.
    key=chapter_service(255,99);code,wide,narrow=account_parse(parent[key],105)
    narrow=list(narrow);narrow[2]=slot;result[key]=account_wire((code,wide,narrow))
    instructions,_=program(profile)
    gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+3636+103*int(profile=='checkpoint-panic')
    if profile=='oversized-code':
        gas=0 # The explicit512-byte chain profile rejects this same large code before guest execution.
    assert gas<=budget
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT)
    activity={row[0]:list(row) for row in services};row=activity.setdefault(99,[99]+[0]*11);row[9]+=1;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas=gas,queue_retained=retained,assigner=42 if retained else 99)


def expected_observations(check_frozen=True):
    """Calculate thirty full transitions with two report releases and selected authorization queue replacement and assigner handoff."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+107)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 8):
            budget = 100000
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99, accumulation_gas=budget)] if slot in (3, 5) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot in (4, 6) else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4, 6) else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            plan['authorization_queues'] = parent[chapter_key(2)][:2560]+queue() if released and profile in ('assign','checkpoint-panic') else parent[chapter_key(2)]
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
        assert fixture['max_service_code_sizes'] == [4096]*5+[512]
    return requests, lines, dict(transitions=36, chains=6, roots=roots, checkpoint_sha256=hashes, traces=traces)
