# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent late upgrade-code activation and current-code selection for retained old-code reports across population changes."""
from pathlib import Path
import json
from owned_history_cache import owned_histories
import current_stf_late_rotation_oracle as late
import current_stf_population_waves_oracle as waves
import current_stf_population_gas_oracle as gas
import current_stf_service_upgrades_oracle as upgrades
from current_stf_effects_oracle import envelope,simulate,gas_definitions
from state_layout_oracle import chapter_key,chapter_service,digest
from state_accounts_oracle import parse as metadata
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key,wire as request_wire
from state_privileges_oracle import wire as privilege_wire
from reporting_scenario_oracle import collect
from reporting_declarations_oracle import declaration

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-upgrades.json'
SOURCES=(late.FIXTURE,waves.FIXTURE,upgrades.FIXTURE,gas.retention.FIXTURE)
NATIVE_DEFINES=(*late.NATIVE_DEFINES,'lateRetention')
PROFILES=('halt','panic','checkpoint-panic','missing-target-code')


def code(profile):
    """Use the original independently authored upgrade21 literal, with its exact checkpoint and terminal behavior."""
    instructions,memory=upgrades.program(profile)
    return envelope(instructions,memory)


def original(profile):
    """Keep both reserved code identities but remove only the initial upgrade program's actual payload."""
    services=upgrades.original(profile);hashed=digest(code(profile))
    del services[value_key('P',99,hashed)];services[request_key(99,hashed,len(code(profile)))]=request_wire(())
    manager,delegator,registrar,assigners,allowances=late.host.privileges(services[chapter_key(12)],2)
    return late.host.original(services,privilege_wire((manager,delegator,registrar,assigners+[0],allowances)))


def outcome(parent,profile,hashed,budget):
    """Code availability and current metadata select actual execution, independently of an old report's signed code hash."""
    if value_key('P',99,hashed) not in parent:return 0,hashed
    if hashed==digest(upgrades.replacement()):return 22,hashed
    assert hashed==digest(code(profile))
    instructions,_=upgrades.program(profile)
    used=simulate(instructions,gas_definitions(),prefix=[b'\0']*5)[0]+1028+103*int(profile=='checkpoint-panic')
    assert used<=budget
    return used,hashed if profile=='panic' else digest(upgrades.replacement())


def advance(parent,profile,slot,gs,ass,reports,payloads):
    """Select whole prefixes while carrying actual current code between prefixes, then independently apply each selected effect."""
    shadow=[metadata(parent[chapter_service(255,99)],105)[0]]
    def charge(sid,budget):
        """Accseq carries the upgraded code into its next actual prefix; code integration remains later than every prefix."""
        if sid==42:return 22
        used,shadow[0]=outcome(parent,profile,shadow[0],budget)
        return used
    plan=waves.projection(parent,'create',slot,ass,reports,charge=charge)
    raw,commitment=late.host.execution.reporting.body(gs,ass,payloads)
    roots=dict(staging=bytes.fromhex(json.loads(late.host.execution.epoch.FIXTURE.read_text())['staging_ring_root']))
    def foundation(ignored_raw,ignored_commitment,outputs):
        """Bind real code extrinsics, actual author statistics and all independently calculated signed header inputs."""
        return late.host.execution.epoch.successor(parent,slot,[],[],roots,cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs,preimages=payloads)
    block,state=late.host.execution.advance(parent,'create',slot,gs,ass,reports,
        processed=plan['processed'],batches=[],ready=plan['ready'],yielded=False,foundation_override=foundation)
    transitions=[]
    for prefix,group in zip(plan['prefixes'],plan['batches']):
        budgets={}
        for hashed in prefix:
            for row in reports[bytes.fromhex(hashed)]['digests']:budgets[row[0]]=budgets.get(row[0],0)+row[3]
        if 42 in group:late.host.charge(state,42,slot,22,operands=group[42])
        if 99 in group:
            prior=dict(state);old=metadata(prior[chapter_service(255,99)],105)[0]
            used,new=outcome(prior,profile,old,budgets[99])
            if value_key('P',99,old) not in prior:
                late.host.charge(state,99,slot,0,operands=group[99])
            else:
                upgrades.effects(state,prior,profile,slot,budgets[99],statistics_config=late.host.statistics_config(state))
                if group[99]>1:late.host.charge(state,99,slot,0,operands=group[99]-1)
            transitions.append(dict(before=old.hex(),after=new.hex(),gas=used,operands=group[99],
                report_codes=[row[1].hex() for hashed in prefix for row in reports[bytes.fromhex(hashed)]['digests'] if row[0]==99]))
    late.integrate(state,payloads,slot)
    return block,state,dict(slot=slot,transitions=transitions,remaining_gas=plan['remaining_gas'],
        processed=[wire[:32].hex() for wire in plan['processed']])


@owned_histories
def cases():
    """Retained old-code reports execute current code only after actual program availability and selected upgrade publication."""
    result=[]
    for profile in PROFILES:
        for retention in ('serial','exact-residual-fit'):
            for supplied in (11,12):
                parent=original(profile);initial=dict(parent);reports={};steps=[];events=[]
                for slot in waves.SLOTS:
                    gs,ass=waves.inputs(parent,slot,True,reports,gas_limits=gas.gas_limits('prefix',retention))
                    payloads=((99,code(profile)),) if slot==supplied else ()
                    block,state,event=advance(parent,profile,slot,gs,ass,reports,payloads)
                    steps.append((block,state,[]));events.append(event);parent=state
                case=dict(name=profile+'-'+retention+'-supply-'+str(supplied),parameters=late.host.parameters(),initial=initial,steps=steps,events=events)
                case['inventory'],case['inventory_rows']=declaration(case,(42,99),blobs=(code(profile),upgrades.replacement()))
                result.append(case)
    return result


def expected_observations(check_frozen=True):
    """Freeze each old-code signed report, current-code transition and complete mathematical state before native replay."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
