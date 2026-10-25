# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent guest-designated staging and original-delegator publication through four actual epoch crossings."""
import json
from functools import lru_cache
from pathlib import Path
import rotation_host_oracle as host
import current_stf_validator_designation_oracle as designation
from current_stf_effects_oracle import immediate, envelope, simulate, gas_definitions
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_privileges_oracle import wire as privileges_wire
from test_codec import reference_encode as natural
from reporting_scenario_oracle import collect

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-designation.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,designation.FIXTURE)
PROFILES = ((6,'designate'),(6,'checkpoint-panic'))+tuple((9,p) for p in
    ('designate','panic','checkpoint-panic','invalid-count','unauthorized','handoff','handoff-panic','handoff-checkpoint'))
NATIVE_DEFINES = ('rotationHosts','rotationDesignations')
SLOTS = (2,10,11,12,13,14,22,23,24,25,34,35,36,37,46,47,48,49)


@lru_cache(maxsize=2)
def staging(count):
    """Known original KZG witnesses bind exact public-key ordering; preserve every opaque336-byte input record."""
    parent = host.execution.population.original()
    if count == 6:
        records = host.execution.epoch.roster(parent[chapter_key(7)])
        root = bytes.fromhex(json.loads(host.execution.epoch.FIXTURE.read_text())['staging_ring_root'])
    else:
        assert count == 9
        records,root,*_ = host.execution.epoch.consensus(parent[chapter_key(4)])
    assert len(records) == count
    return b''.join(records),root


def program(count,profile,sid):
    """Literal manager42 redirects delegation while original delegator99 proposes actual six/nine-member staging."""
    if sid == 42:
        instructions = [immediate(7,42),immediate(8,196608),immediate(9,42),immediate(10,0),
                        immediate(11,196620),immediate(12,0),bytes([10,16])]
        memory = bytes(12); checkpoint = profile == 'handoff-checkpoint'
        panic = profile in ('handoff-panic','handoff-checkpoint')
    else:
        instructions = [immediate(7,196608),immediate(8,5 if profile=='invalid-count' else count),bytes([10,18])]
        memory = staging(count)[0]; checkpoint = profile == 'checkpoint-panic'
        panic = profile in ('panic','checkpoint-panic')
    if checkpoint:
        instructions.append(bytes([10,19])) # Only the explicitly selected prefix survives exceptional termination.
    instructions.append(b'\0' if panic else bytes([50,0]))
    return instructions,memory


def original(count,profile):
    """Code, exact supervisor metadata and original manager/delegator identity exist before any report signature."""
    services = designation.transfers.original('halt')
    for sid in ((42,99) if profile.startswith('handoff') else (99,)):
        key = chapter_service(255,sid);code,wide,narrow = account_parse(services[key],105)
        old = services.pop(value_key('P',sid,code));del services[request_key(sid,code,len(old))]
        raw = envelope(*program(count,profile,sid));hashed = digest(raw)
        services[value_key('P',sid,hashed)] = raw;services[request_key(sid,hashed,len(raw))] = request_wire((1,))
        wide = list(wide);wide[4] += len(raw)-len(old);services[key] = account_wire((hashed,wide,narrow))
    return host.original(services,privileges_wire((42 if profile.startswith('handoff') else 0,
        42 if profile=='unauthorized' else 99,0,[0]*3,[])))


def foundation(parent,slot):
    """Select a commitment only for its exact original membership, independently deriving every delayed promotion."""
    rows = b''.join(host.execution.epoch.roster(parent[chapter_key(7)]))
    candidates = [root for count in (6,9) for records,root in (staging(count),) if rows == records]
    assert len(candidates) == 1
    def advance(raw,commitment,outputs):
        """Safrole consumes prior staging before same-block guest effects can modify its successor."""
        return host.execution.epoch.successor(parent,slot,[],[],dict(staging=candidates[0]),cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs)
    return advance


def effects(state,parent,count,profile,slot):
    """Original delegator's selected output writes staging even if the original manager simultaneously hands off its role."""
    manager,delegator,registrar,assigners,allowances = host.privileges(parent[chapter_key(12)])
    if delegator == 99 and profile not in ('panic','invalid-count','unauthorized'):
        state[chapter_key(7)] = natural(count)+staging(count)[0]
    if profile.startswith('handoff') and profile != 'handoff-panic':
        state[chapter_key(12)] = privileges_wire((manager,42,registrar,assigners,allowances))
    for sid in ((42,99) if profile.startswith('handoff') else (99,)):
        instructions,_ = program(count,profile,sid)
        gas = simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]
        gas += 422 if sid == 42 else 1100+302*(5 if profile=='invalid-count' else count)
        gas += 103*int(sid==42 and profile=='handoff-checkpoint' or sid==99 and profile=='checkpoint-panic')
        host.charge(state,sid,slot,gas,1)


def cases():
    """Actual reports release at four boundaries and their following blocks, including prior-nine votes before shrinkage."""
    result = []
    for count,profile in PROFILES:
        parent = original(count,profile);initial = dict(parent);reports = {};steps = []
        for slot in SLOTS:
            gs = []
            if slot in (10,12,23,24,35,36,47,48):
                for core,sid in (((0,42),(1,99)) if profile.startswith('handoff') else ((1,99),)):
                    item = host.execution.guarantee(parent,core,slot,sid)
                    gs.append(item);reports[item['report'][:32]] = item['layout']
            released = slot in (12,13,24,25,36,37,48,49)
            votes = 2*len(host.execution.epoch.roster(parent[chapter_key(8)]))//3+1
            ass = host.execution.rotation.assurances(parent,votes,3 if profile.startswith('handoff') else 2) if released else []
            block,state = host.advance(parent,slot,gs,ass,reports,foundation=foundation(parent,slot))
            if released:
                effects(state,parent,count,profile,slot)
            steps.append((block,state,[]));parent = state
        result.append(dict(name=str(count)+'-'+profile,parameters=host.parameters(),initial=initial,steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Freeze independently derived complete checkpoints, roots and signatures before running the native client."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
