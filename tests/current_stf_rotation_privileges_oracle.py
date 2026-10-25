# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP manager/assigner precedence, posterior queues and allowance scheduling across6/9/6 rosters."""
from pathlib import Path
import rotation_host_oracle as host
import current_stf_bless_allowances_oracle as bless
import current_stf_authorization_assign_oracle as assign
import current_stf_role_precedence_oracle as roles
import current_stf_manager_handoff_oracle as handoff
from current_stf_effects_oracle import immediate, envelope, simulate, gas_definitions
from state_layout_oracle import chapter_key, chapter_service, digest
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_privileges_oracle import wire as privileges_wire
from rotation_host_oracle import privileges as privileges_parse
from reporting_scenario_oracle import collect

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-privileges.json'
SOURCES = (host.execution.population.population.FIXTURE, host.execution.epoch.FIXTURE,
           bless.FIXTURE, assign.FIXTURE, roles.FIXTURE, handoff.FIXTURE)
FAMILIES = (('manager', handoff.PROFILES), ('allowances', bless.PROFILES), ('assignment', assign.PROFILES[:-1]), ('precedence', roles.PROFILES))


def program(family, profile, sid):
    """Encode three-core memory layouts directly; indices and raw table lengths stay independently explicit."""
    if family == 'manager':
        instructions = [immediate(7,99 if profile=='self' else 42),immediate(8,196608),
                        immediate(9,0),immediate(10,0),immediate(11,196620),immediate(12,0),bytes([10,16])]
        memory = bytes(12); terminal = profile in ('panic','checkpoint-panic')
    elif family == 'allowances':
        pairs = bless.pairs(profile)
        memory = bytes(12)+b''.join(s.to_bytes(4,'little')+g.to_bytes(8,'little') for s,g in pairs)
        instructions = [immediate(7,99), immediate(8,196608), immediate(9,0), immediate(10,0),
                        immediate(11,196620), immediate(12,len(pairs)), bytes([10,16])]
        terminal = profile in ('panic','checkpoint-panic')
    elif family == 'assignment':
        core = 3 if profile == 'invalid-core' else 1
        nominee = 2**32+42 if profile == 'invalid-assigner' else 42
        instructions = [immediate(7,core),immediate(8,196608),immediate(9,nominee),bytes([10,17])]
        memory = assign.queue(); terminal = profile in ('panic','checkpoint-panic')
    else:
        if sid == 42:
            instructions = [immediate(7,1),immediate(8,196608),immediate(9,99),bytes([10,17])]
            memory = assign.queue(); terminal = profile == 'assigner-panic'
        else:
            instructions = [immediate(7,99),immediate(8,196608),immediate(9,0),immediate(10,0),
                            immediate(11,196620),immediate(12,0),bytes([10,16])]
            role = 42 if profile == 'manager-keeps' else 0
            memory = (42).to_bytes(4,'little')+role.to_bytes(4,'little')+bytes(4)
            terminal = profile in ('manager-panic','manager-checkpoint')
    checkpoint = profile == 'checkpoint-panic' or family == 'precedence' and sid == 99 and profile == 'manager-checkpoint'
    if checkpoint:
        instructions.append(bytes([10,19])) # Exact selected privileged output survives the later panic.
    if family == 'manager':
        instructions += [immediate(7,99),bytes([10,16])] # Changed authority refuses the caller's attempt to restore itself.
    if family == 'assignment':
        instructions += [immediate(7,core),immediate(8,196608),immediate(9,nominee if profile=='invalid-assigner' else 99),bytes([10,17])]
    instructions.append(b'\0' if terminal else bytes([50,0]))
    return instructions, memory


def original(family, profile):
    """Install literal available code and honest metadata in the independently authored three-core population original."""
    services = bless.transfers.original('halt')
    for sid in ((42,99) if family == 'precedence' else (99,)):
        key = chapter_service(255,sid); code,wide,narrow = account_parse(services[key],105)
        old = services.pop(value_key('P',sid,code)); del services[request_key(sid,code,len(old))]
        instructions,memory = program(family,profile,sid)
        raw = envelope(instructions,memory); hashed = digest(raw)
        services[value_key('P',sid,hashed)] = raw; services[request_key(sid,hashed,len(raw))] = request_wire((1,))
        wide = list(wide); wide[4] += len(raw)-len(old); services[key] = account_wire((hashed,wide,narrow))
    privileges = (42 if profile=='unauthorized' else 99,0,0,[0]*3,[]) if family in ('manager','allowances') else (0,0,0,[99]*3,[])
    if family == 'precedence': privileges = (99,0,0,[42]*3,[])
    return host.original(services,privileges_wire(privileges))


def selected(parent,family,profile,invoked):
    """Apply GP accpar R to original-role contributions and choose queues from the original producer only."""
    manager,delegator,registrar,assigners,allowances = privileges_parse(parent[chapter_key(12)],3)
    assigners = list(assigners); queues = parent[chapter_key(2)]
    if family == 'manager' and invoked and manager == 99 and profile not in ('panic','unauthorized'):
        manager = 99 if profile == 'self' else 42
    if family == 'allowances' and invoked and profile not in ('panic','unauthorized'):
        allowances = sorted(set(bless.pairs(profile)))
    if family == 'assignment' and invoked and profile in ('assign','checkpoint-panic') and assigners[1] == 99:
        assigners[1] = 42
        queues = queues[:2560]+assign.queue()+queues[5120:]
    if family == 'precedence' and invoked:
        old = assigners[1]
        proposal = old if profile == 'manager-panic' else (42 if profile == 'manager-keeps' else 0)
        own = 99 if old == 42 and profile != 'assigner-panic' else old
        assigners[1] = proposal if proposal != old else own
        if profile != 'manager-panic':
            assigners[2] = 0 # The literal three-core manager table also redirects the third role.
        if old == 42 and profile != 'assigner-panic':
            queues = queues[:2560]+assign.queue()+queues[5120:]
    return privileges_wire((manager,delegator,registrar,assigners,allowances)),queues


def effects(state,parent,family,profile,slot,invoked):
    """Count actual report and empty-operand invocations, literal host costs and selected checkpoint gas."""
    prior = privileges_parse(parent[chapter_key(12)],3)[4]
    active = ({42,99} if family == 'precedence' else {99}) if invoked else set()
    active.update(s for s,g in prior if g > 0)
    for sid in sorted(active):
        if sid == 42 and family == 'allowances':
            gas = 22
        else:
            instructions,_ = program(family,profile,sid)
            gas = simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]
            if family == 'manager': gas += 844
            elif family == 'assignment': gas += 3636
            elif family == 'precedence' and sid == 42: gas += 1818
            else: gas += 422+20*(len(bless.pairs(profile)) if family=='allowances' else 0)
            gas += 103*int(profile=='checkpoint-panic' or family=='precedence' and sid==99 and profile=='manager-checkpoint')
        host.charge(state,sid,slot,gas,int(invoked and (sid == 99 or family == 'precedence')))


def cases():
    """Release reports at growth, within the larger epoch, at shrinkage and after shrinking with exact prior quorum."""
    result = []
    for family,profiles in FAMILIES:
        for profile in profiles:
            parent = original(family,profile); initial = dict(parent); reports = {}; steps = []
            for slot in host.execution.SLOTS:
                gs = []
                if slot in (10,12,23,24):
                    for core,sid in (((0,42),(1,99)) if family=='precedence' else ((1,99),)):
                        item = host.execution.guarantee(parent,core,slot,sid)
                        gs.append(item); reports[item['report'][:32]] = item['layout']
                count = {12:5,13:7,24:7,25:5}.get(slot,0)
                bits = 3 if family=='precedence' else 2
                ass = host.execution.rotation.assurances(parent,count,bits) if count else []
                invoked = bool(count)
                privilege,queues = selected(parent,family,profile,invoked)
                block,state = host.advance(parent,slot,gs,ass,reports,queues=queues)
                state[chapter_key(12)] = privilege; state[chapter_key(2)] = queues
                effects(state,parent,family,profile,slot,invoked)
                steps.append((block,state,[])); parent = state
            result.append(dict(name=family+'-'+profile,parameters=host.parameters(),initial=initial,steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Bind full signed blocks, every byte/root and independent source inputs before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
