# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent recent/lookup anchor provenance and inclusive age boundaries after validator growth and shrinkage."""
import copy
import json
from pathlib import Path
import current_stf_population_reporting_oracle as population
import current_stf_epoch_oracle as epoch
import current_stf_reporting_oracle as reporting
from current_stf_oracle import history,tree
from state_layout_oracle import chapter_key,digest
from reporting_scenario_oracle import collect

FIXTURE=Path(__file__).parent/'fixtures/current-stf-population-anchors.json'
SOURCES=(population.FIXTURE,population.population.FIXTURE,epoch.FIXTURE)
AGE=14400


def parameters(age=AGE):
    """Author the complete122-byte configured tuple with explicit three-core/twelve-slot and lookup-age fields."""
    wire=bytearray([255]*122);wire[:24]=bytes(24)
    for offset,width,value in ((24,2,3),(30,4,12),(74,4,age),(82,2,80),(98,4,512),(110,4,128),(118,4,12)):
        wire[offset:offset+width]=value.to_bytes(width,'little')
    return bytes(wire)


def validate(parent,slot,gs,ass,anchors):
    """Recent tuples bind one parent record; historical lookups bind header/slot and its child's committed complete root."""
    population.validate(parent,slot,gs,ass)
    last=history(parent[chapter_key(3)])[0][-1][0]
    recent=last[:32]+last[96:100]+tree(list(parent.items()))[0]+last[32:64]
    for item in gs:
        header=item['layout']['header']
        assert header[104:204]==recent,'anchor/InvalidRecentAnchor'
        stamp=int.from_bytes(header[236:240],'little')
        assert slot<=AGE or stamp>=slot-AGE,'anchor/LookupTooOld'
        found=anchors.get(header[204:236])
        assert found is not None and found[0]==stamp,'anchor/MissingLookupAnchor'
        assert found[1]==header[240:272],'anchor/WrongLookupState'


def set_lookup(parent,slot,gs,lookup):
    """Replace only the explicit historical lookup tuple, then independently sign the final report hash."""
    header_hash,stamp,root=lookup
    for item in gs:
        item['layout']['header']=item['layout']['header'][:204]+header_hash+stamp.to_bytes(4,'little')+root
        population.resign(item,population.epoch_reporting.credentials(parent,slot,item['slot'])[0])


def seal(parent,slot,gs,ass):
    """Seal even intentionally inadmissible report bodies without constructing a hypothetical reported successor."""
    raw,commitment=reporting.body(gs,ass)
    roots=dict(staging=bytes.fromhex(json.loads(epoch.FIXTURE.read_text())['staging_ring_root']))
    return epoch.successor(parent,slot,[],[],roots,cores=3,body_override=raw,extrinsic_override=commitment)[0]


def cases():
    """Old lookups come from both sides of growth and remain independently authenticated after shrinkage."""
    result=[]
    for origin in (2,13):
        parent=population.original();initial=dict(parent);steps=[]
        first=history(parent[chapter_key(3)])[0][-1][0]
        anchors={first[:32]:(1,tree(list(parent.items()))[0])};lookup=None
        slots=(*population.SLOTS,origin+AGE-1,origin+AGE,origin+AGE+1)
        for slot in slots:
            if slot in population.SLOTS: gs,ass=population.inputs(parent,0,slot)
            else:
                gs=[population.guarantee(parent,c,200+(slot-origin-AGE),slot,slot) for c in range(2)] if slot>=origin+AGE else []
                ass=population.epoch_reporting.assurances(parent,5,3) if slot==origin+AGE+1 else []
                if slot==origin+AGE:set_lookup(parent,slot,gs,lookup)
            refused=[]
            if slot==origin+AGE:
                for offset,reason in ((140,'anchor/InvalidRecentAnchor'),(240,'anchor/WrongLookupState'),
                                      (204,'anchor/MissingLookupAnchor'),(236,'anchor/MissingLookupAnchor')):
                    bad=copy.deepcopy(gs);header=bytearray(bad[0]['layout']['header'])
                    if offset==236:header[236:240]=(origin+1).to_bytes(4,'little')
                    else:header[offset]^=1
                    bad[0]['layout']['header']=bytes(header)
                    population.resign(bad[0],population.epoch_reporting.credentials(parent,slot,bad[0]['slot'])[0])
                    try:validate(parent,slot,bad,ass,anchors)
                    except AssertionError as error:assert str(error)==reason,(error,reason)
                    else:raise AssertionError('invalid anchor accepted')
                    refused.append((seal(parent,slot,bad,ass),reason))
            if slot==origin+AGE+1:
                bad=copy.deepcopy(gs);set_lookup(parent,slot,bad,lookup)
                try:validate(parent,slot,bad,ass,anchors)
                except AssertionError as error:assert str(error)=='anchor/LookupTooOld'
                else:raise AssertionError('expired lookup accepted')
                refused.append((seal(parent,slot,bad,ass),'anchor/LookupTooOld'))
            validate(parent,slot,gs,ass,anchors)
            wire,after=population.advance(parent,slot,gs,ass)
            fixed=history(after[chapter_key(3)])[0][-1][0];root=tree(list(after.items()))[0]
            anchors[fixed[:32]]=(slot,root)
            if slot==origin:lookup=(fixed[:32],slot,root)
            steps.append((wire,after,refused));parent=after
        result.append(dict(name='lookup-from-'+str(origin),parameters=parameters(),initial=initial,steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Bind explicit trusted parameters, every independently signed refusal and all complete successor maps."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
