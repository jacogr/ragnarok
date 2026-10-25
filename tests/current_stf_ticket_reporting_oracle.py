# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent ticket-contest, winner/fallback sealing and reporting through six/six/nine active rosters."""
import copy
import json
from pathlib import Path
import current_stf_population_reporting_oracle as population
import current_stf_epoch_reporting_oracle as rotation
import current_stf_epoch_oracle as epoch
import current_stf_reporting_oracle as reporting
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key
from reporting_scenario_oracle import collect
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-ticket-reporting.json'
SOURCES = (epoch.FIXTURE, population.population.FIXTURE)
SLOTS = ((2,3,4,5,6,10,11,12,13,23,24,25),
         (2,3,4,5,6,12,13,23,24,25), (2,3,6,10,11,12,13,23,24,25))
NAMES = ('saturated-winners','skipped-tail-fallback','incomplete-fallback')


def original():
    """Original published membership witnesses bind pending-six and later pending-nine, before state roots are calculated."""
    parent=population.original()
    old=decode_checkpoint(bytes.fromhex(json.loads(epoch.FIXTURE.read_text())['parent_checkpoint']))
    nine=epoch.consensus(parent[chapter_key(4)])[0]
    parent[chapter_key(4)]=old[chapter_key(4)]
    parent[chapter_key(7)]=natural(9)+b''.join(nine)
    parent[chapter_key(6)]=bytes(128)
    return parent


def staging_root():
    """Read only the attributed nine-member KZG root; no captured successor supplies an expected byte."""
    captured=decode_checkpoint(bytes.fromhex(json.loads(population.population.FIXTURE.read_text())['parent_checkpoint']))
    return epoch.consensus(captured[chapter_key(4)])[1]


def tickets_wire(submitted):
    """Canonical ticket count, entry index and exact attributed proof bytes bind the body commitment."""
    return natural(len(submitted))+b''.join(bytes([t['attempt']])+bytes.fromhex(t['proof']) for t in submitted)


def advance(parent,slot,guaranteed,assured,submitted,bank):
    """Apply independent ticket/Safrole state before report assignment, availability and resized statistics."""
    old,released,reporters,changed=population.validate(parent,slot,guaranteed,assured)
    raw,commitment=reporting.body(guaranteed,assured,tickets=tickets_wire(submitted))
    roots=dict(pending=epoch.consensus(parent[chapter_key(4)])[1], staging=staging_root())
    child,result=epoch.successor(parent,slot,submitted,bank,roots,cores=3,
        body_override=raw,extrinsic_override=commitment)
    active,previous=epoch.roster(result[chapter_key(8)]),epoch.roster(result[chapter_key(9)])
    selected={i for i,row in enumerate(active) if row[32:64] in reporters}
    crossed=slot//12>int.from_bytes(parent[chapter_key(11)],'little')//12
    result=reporting.apply_reporting(parent,result,slot,guaranteed,assured,old,released,
        reporters=selected,assurance_previous=crossed,cores=3,current_validators=len(active),
        previous_validators=len(previous),population_changed=changed)
    return child,result


def cases():
    """Saturated/unsaturated contests share authentic reports, prior assurances and exact boundary refusals."""
    bank=epoch.bank_records(json.loads(epoch.FIXTURE.read_text()));result=[]
    for name,slots in zip(NAMES,SLOTS):
        parent=original();initial=dict(parent);steps=[]
        for slot in slots:
            submitted=bank[(slot-2)*3:(slot-1)*3] if 2<=slot<=5 else []
            guaranteed=[]
            if slot in (3,10,12,23,24):
                count=3 if slot==24 else 2
                for core in range(count):
                    stamp=slot-1 if slot in (12,24) and core<2 else slot
                    guaranteed.append(population.guarantee(parent,core,slot,slot,stamp))
            count={6:5,11:5,13:5,24:5,25:7}.get(slot,0)
            assured=rotation.assurances(parent,count,7 if slot==25 else 3) if count else []
            refused=[]
            if slot==24:
                altered=copy.deepcopy(guaranteed);item=altered[-1]
                item['layout']['header']=item['layout']['header'][:68]+(6).to_bytes(2,'little')+item['layout']['header'][70:]
                population.resign(item,rotation.credentials(parent,slot,item['slot'])[0])
                try: population.validate(parent,slot,altered,assured)
                except AssertionError as error: assert str(error)=='credential/WrongErasureShards'
                else: raise AssertionError('invalid erasure width accepted')
                wire,_=advance_unchecked(parent,slot,altered,assured,submitted,bank)
                refused.append((wire,'credential/WrongErasureShards'))
            child,after=advance(parent,slot,guaranteed,assured,submitted,bank)
            steps.append((child,after,refused));parent=after
        result.append(dict(name=name,initial=initial,steps=steps))
    return result


def advance_unchecked(parent,slot,guaranteed,assured,submitted,bank):
    """Seal a deliberately inadmissible report body independently without using its hypothetical successor."""
    raw,commitment=reporting.body(guaranteed,assured,tickets=tickets_wire(submitted))
    roots=dict(staging=staging_root())
    return epoch.successor(parent,slot,submitted,bank,roots,cores=3,body_override=raw,extrinsic_override=commitment)


def expected_observations(check_frozen=True):
    """Freeze every complete expected state and exact refused signed wire before native execution."""
    return collect(cases(),FIXTURE,SOURCES,check_frozen)
