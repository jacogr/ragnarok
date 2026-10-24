# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map original manager/assigner precedence, posterior queues and selected privileged outcomes cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-role-precedence.json'
PROFILES = ('manager-overrides', 'manager-keeps', 'manager-panic', 'manager-checkpoint', 'assigner-panic')
PAYLOAD = b'R'


from current_stf_authorization_assign_oracle import queue
from state_privileges_oracle import wire as privileges_wire


def programs(profile):
    """Manager99 and original assigner42 operate from one prior, with visibly different role proposals."""
    assigner=[immediate(7,1),immediate(8,196608),immediate(9,99),bytes([10,17])]
    assigner.append(b'\0' if profile=='assigner-panic' else bytes([50,0]))
    manager=[immediate(7,99),immediate(8,196608),immediate(9,0),immediate(10,0),immediate(11,196616),immediate(12,0),bytes([10,16])]
    if profile=='manager-checkpoint':
        manager.append(bytes([10,19])) # A real selected manager proposal retains precedence after panic.
    manager.append(b'\0' if profile in ('manager-panic','manager-checkpoint') else bytes([50,0]))
    roles=(42).to_bytes(4,'little')+(42 if profile=='manager-keeps' else 0).to_bytes(4,'little')
    return ((assigner,queue()),(manager,roles))


def original(profile):
    """Only the original manager and assigner may supply their respective GP R/queue contributions."""
    parent=transfers.original('halt')
    for sid,(instructions,memory) in zip((42,99),programs(profile)):
        key=chapter_service(255,sid);old_hash,wide,narrow=account_parse(parent[key],105)
        old=parent.pop(value_key('P',sid,old_hash));del parent[request_key(sid,old_hash,len(old))]
        raw=envelope(instructions,memory);hashed=digest(raw)
        parent[value_key('P',sid,hashed)]=raw;parent[request_key(sid,hashed,len(raw))]=request_wire((1,))
        wide=list(wide);wide[4]+=len(raw)-len(old);parent[key]=account_wire((hashed,wide,narrow))
    parent[chapter_key(12)]=privileges_wire((99,0,0,[42,42],[]))
    return parent


def effects(result,parent,profile,slot,budget):
    """R chooses a changed manager proposal, otherwise the original assigner's proposal; queue always uses original assigner42."""
    manager_retained=profile!='manager-panic';assigner_retained=profile!='assigner-panic'
    proposed=42 if profile=='manager-keeps' or not manager_retained else 0
    role=proposed if proposed!=42 else (99 if assigner_retained else 42)
    result[chapter_key(12)]=privileges_wire((99,0,0,[42,role],[]))
    if assigner_retained:
        result[chapter_key(2)]=parent[chapter_key(2)][:2560]+queue() # Manager redirection cannot substitute the queue's original producer.
    (assigner,_),(manager,_)=programs(profile)
    gas42=simulate(assigner,gas_definitions(),prefix=[b'\0']*5)[0]+1818
    gas99=simulate(manager,gas_definitions(),prefix=[b'\0']*5)[0]+422+103*int(profile=='manager-checkpoint')
    assert max(gas42,gas99)<=budget
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT)
    activity={row[0]:list(row) for row in services}
    for sid,gas in ((42,gas42),(99,gas99)):
        key=chapter_service(255,sid);code,wide,narrow=account_parse(parent[key],105)
        narrow=list(narrow);narrow[2]=slot;result[key]=account_wire((code,wide,narrow))
        row=activity.setdefault(sid,[sid]+[0]*11);row[9]+=1;row[11]+=gas # Actual work survives terminal exceptional selection.
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas42=gas42,gas99=gas99,manager_proposal=proposed,selected_assigner=role,queue_retained=assigner_retained)


def expected_observations(check_frozen=True):
    """Calculate thirty full transitions with two report releases and original manager/assigner role precedence and posterior authorization queue."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+113)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 6):
            budget = 100000
            gs = [pipeline.guarantee(parent, initial, core, slot, service=sid, accumulation_gas=budget) for core,sid in ((0,42),(1,99))] if slot == 3 else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot == 4 else 0, 3)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot == 4 else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            plan['authorization_queues'] = parent[chapter_key(2)][:2560]+queue() if released and profile!='assigner-panic' else parent[chapter_key(2)]
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
        assert fixture['max_service_code_size'] == 4096
    return requests, lines, dict(transitions=20, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
