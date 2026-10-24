# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent selected validator designation, staging-to-pending-to-active rotation and complete maps."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-validator-designation.json'
PROFILES = ('designate', 'panic', 'checkpoint-panic', 'invalid-count', 'unauthorized')


from state_privileges_oracle import wire as privileges_wire
from current_stf_oracle import decode_checkpoint
from state_consensus_oracle import wire as consensus_wire
import current_stf_epoch_oracle as epoch


def staging():
    """Reuse the attributed original six-record staging input and KZG commitment, never an observed STF successor."""
    fixture=json.loads(epoch.FIXTURE.read_text())
    assert fixture['graypaper_commit']=='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    original=decode_checkpoint(bytes.fromhex(fixture['parent_checkpoint']))
    records=epoch.roster(original[chapter_key(7)])
    assert [epoch.PUBLIC[row[:32]] for row in records]==[6,5,4,3,2,1]
    return b''.join(records),bytes.fromhex(fixture['staging_ring_root'])


def program(profile):
    """Designate consumes six genuine336-byte records; invalid count5 remains memory-readable before HUH."""
    instructions=[immediate(7,196608),immediate(8,5 if profile=='invalid-count' else 6),bytes([10,18])]
    if profile=='checkpoint-panic':
        instructions.append(bytes([10,19])) # Select the exact staging roster before exceptional termination.
    instructions.append(b'\0' if profile in ('panic','checkpoint-panic') else bytes([50,0]))
    return instructions,staging()[0]


def original(profile):
    """Original delegation is committed before report signing and code availability is honest under the4096-byte profile."""
    parent=transfers.original('halt');key=chapter_service(255,99)
    old_hash,wide,narrow=account_parse(parent[key],105)
    old=parent.pop(value_key('P',99,old_hash));del parent[request_key(99,old_hash,len(old))]
    instructions,memory=program(profile);raw=envelope(instructions,memory);hashed=digest(raw)
    parent[value_key('P',99,hashed)]=raw;parent[request_key(99,hashed,len(raw))]=request_wire((1,))
    wide=list(wide);wide[4]+=len(raw)-len(old);parent[key]=account_wire((hashed,wide,narrow))
    parent[chapter_key(12)]=privileges_wire((0,42 if profile=='unauthorized' else 99,0,[0,0],[]))
    return parent


def foundation(parent,slot):
    """Select the known KZG input only for its exact staged membership; independently calculate all epoch/global effects."""
    pending,root,*_=epoch.consensus(parent[chapter_key(4)])
    staged,staged_root=staging()
    current=b''.join(epoch.roster(parent[chapter_key(7)]))
    if current==staged:
        root=staged_root # The input witness belongs to this exact six-record ordering.
    else:
        assert epoch.roster(parent[chapter_key(7)])==pending
    def advance(raw,commitment,outputs):
        """Independent Thin seals/markers, entropy, statistics and roster rotation precede report and guest composition."""
        return epoch.successor(parent,slot,[],[],{'staging':root},body_override=raw,extrinsic_override=commitment,outputs=outputs)
    return advance


def effects(result,parent,profile,slot,budget):
    """Only the selected original delegator writes C7; pending/active changes wait for their actual epoch boundaries."""
    retained=profile in ('designate','checkpoint-panic')
    if retained:
        result[chapter_key(7)]=b'\6'+staging()[0]
    key=chapter_service(255,99);code,wide,narrow=account_parse(parent[key],105)
    narrow=list(narrow);narrow[2]=slot;result[key]=account_wire((code,wide,narrow))
    instructions,_=program(profile);count=5 if profile=='invalid-count' else 6
    gas=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+1100+302*count+103*int(profile=='checkpoint-panic')
    assert gas<=budget
    (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],DEFAULT)
    activity={row[0]:list(row) for row in services};row=activity.setdefault(99,[99]+[0]*11);row[9]+=1;row[11]+=gas
    result[chapter_key(13)]=statistics_wire((current,previous,cores,[tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot,gas=gas,staging_retained=retained)


def expected_observations(check_frozen=True):
    """Calculate fifty full transitions with selected staging observed through two epoch rotations."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+118)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in (2,3,4,5,11,12,13,23,24,25):
            budget = 100000
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99, accumulation_gas=budget)] if slot == 3 else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot == 4 else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot == 4 else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            plan['foundation'] = foundation(parent,slot)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released) == 1
                traces[-1].append(effects(result, parent, profile, slot, budgets[released[0][:32]]))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+str(slot)+' '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
        assert fixture['max_service_code_size'] == 4096
        assert fixture['epoch_input_sha256'] == hashlib.sha256(epoch.FIXTURE.read_bytes()).hexdigest()
    return requests, lines, dict(transitions=50, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
