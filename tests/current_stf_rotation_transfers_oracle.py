# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent deferred/direct transfers, all balance pools, literal memos and gas refusal boundaries across6/9/6 rosters."""
import json
from pathlib import Path
import rotation_host_oracle as host
import current_stf_transfers_oracle as deferred
import current_stf_transfer_pools_oracle as pools
import current_stf_transfer_admission_oracle as admission
import current_stf_transfer_memos_oracle as memos
from state_layout_oracle import chapter_key
from state_privileges_oracle import wire as privileges_wire
from reporting_scenario_oracle import collect

FIXTURE = Path(__file__).parent/'fixtures/current-stf-rotation-transfers.json'
SOURCES = (host.execution.population.population.FIXTURE,host.execution.epoch.FIXTURE,
           deferred.FIXTURE,pools.FIXTURE,admission.FIXTURE,memos.FIXTURE)
FAMILIES = (('deferred',deferred,deferred.MODES),('pools',pools,pools.PROFILES),
            ('admission',admission,admission.PROFILES),('memos',memos,memos.PROFILES))


def name(family,profile):
    """Stable semantic identities preserve the four ordered source/destination pool selections."""
    return family+'-'+('-'.join(map(str,profile)) if isinstance(profile,tuple) else profile)


def foundation(parent,slot,outputs):
    """Bind independently selected receiver yields into history/MMR while deriving actual roster promotions."""
    root = bytes.fromhex(json.loads(host.execution.epoch.FIXTURE.read_text())['staging_ring_root'])
    def advance(raw,commitment,ignored_outputs):
        """Only literal independently fetched memo bytes supply accumulation outputs."""
        return host.execution.epoch.successor(parent,slot,[],[],dict(staging=root),cores=3,
            body_override=raw,extrinsic_override=commitment,outputs=outputs)
    return advance


def cases():
    """Four real releases straddle growth/shrinkage; direct credit and deferred receiver participation stay distinct."""
    result = []
    for family,oracle,profiles in FAMILIES:
        for profile in profiles:
            args = profile if isinstance(profile,tuple) else (profile,)
            services = oracle.original(*args)
            manager,delegator,registrar,assigners,allowances = host.privileges(services[chapter_key(12)],2)
            parent = host.original(services,privileges_wire((manager,delegator,registrar,assigners+[0],allowances)))
            initial = dict(parent);reports = {};steps = []
            for slot in host.execution.SLOTS:
                gs = []
                if slot in (10,12,23,24):
                    item = host.execution.guarantee(parent,1,slot,99)
                    gs.append(item);reports[item['report'][:32]] = item['layout']
                count = {12:5,13:7,24:7,25:5}.get(slot,0)
                ass = host.execution.rotation.assurances(parent,count,2) if count else []
                outputs = ((42,memos.fetched(profile)),) if family=='memos' and count and profile!='panic' else ()
                block,state = host.advance(parent,slot,gs,ass,reports,foundation=foundation(parent,slot,outputs))
                if count:
                    oracle.effects(state,*args,slot,statistics_config=host.statistics_config(state))
                steps.append((block,state,[]));parent = state
            result.append(dict(name=name(family,profile),parameters=host.parameters(),initial=initial,steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Freeze every full signed transition and map before any native execution; original fixture answers remain unchanged."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
