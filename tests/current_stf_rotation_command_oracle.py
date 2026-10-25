# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete host-history operator bundles retain configured trust and genuine signed TraceSteps."""
import copy
import hashlib
import json
from pathlib import Path
import rotation_replay_oracle as suite
import current_stf_population_anchors_oracle as anchors
import current_stf_rotation_trace_oracle as traces
import current_stf_trace_command_oracle as original_command
from current_stf_trace_genesis_oracle import initial_header
from current_stf_oracle import checkpoint,history,tree
from state_trace_wire_oracle import wire as raw_state,prefix
from state_layout_oracle import chapter_key,digest
from reporting_scenario_oracle import validate_frozen
import block_oracle

FIXTURE=Path(__file__).parent/'fixtures/current-stf-rotation-command.json'
SOURCES=(*suite.SOURCES,traces.FIXTURE,original_command.FIXTURE)
SELECTION=tuple(range(len(suite.FAMILIES)))


NATIVE_DEFINES=suite.NATIVE_DEFINES

def expected_observations(check_frozen=True):
    """Author every file, trusted parameter tuple and command result before any native policy input or command runs."""
    chains=suite.cases();jobs=[];answers=[];roots=[];hashes=[];origins=[];header=initial_header()
    for index in SELECTION:
        case=chains[index];initial=case['initial']
        assert history(initial[chapter_key(3)])[0][-1][0][:32]==digest(header)
        genesis=header+raw_state(list(initial.items()))
        parameters=case.get('parameters',anchors.parameters(0xffffffff))
        steps=[];parent=initial;row=[];checks=[]
        for block,after,_ in case['steps']:
            steps.append(raw_state(list(parent.items()))+block+raw_state(list(after.items())))
            row.append(tree(list(after.items()))[0].hex());checks.append(hashlib.sha256(checkpoint(list(after.items()))).hexdigest());parent=after
        jobs.append(dict(label=case['name'],config=original_command.chain_config(genesis,parameters),genesis=genesis,steps=steps))
        answers.append('C None '+str(len(steps))+' '+row[-1]);roots.append(row);hashes.append(checks);origins.append(list(suite.origins()[index]))
    first=jobs[0];before,extent=prefix(first['steps'][0]);config=(3,9,*block_oracle.TINY[2:])
    length,_,_=block_oracle.parse('B',first['steps'][0][extent:],config)
    block=first['steps'][0][extent:extent+length];after=first['steps'][0][extent+length:]
    def refusal(label,genesis,steps,error,checked,detail='-'):
        """Rejected standalone commands retain no successful final root, including a valid prefix before a later failure."""
        job=copy.deepcopy(first);job.update(label=label,genesis=genesis,steps=steps);jobs.append(job)
        answers.append('C '+error+' '+str(checked)+' '+detail)
    assert jobs[1]['genesis'][:297]==first['genesis'][:297] and jobs[1]['genesis'][297:]!=first['genesis'][297:]
    refusal('wrong-genesis-root',jobs[1]['genesis'],first['steps'][:1],'BootstrapFailure',0,'StateMismatch')
    refusal('trailing-genesis',first['genesis']+b'\0',first['steps'][:1],'TrailingGenesis',0)
    refusal('recommitted-wrong-post',first['genesis'],[raw_state(before)+block+raw_state(before)],'ImportFailure',0,'PostStateMismatch')
    refusal('trailing-trace',first['genesis'],[first['steps'][0]+b'\0'],'TraceFailure',0,'TrailingBytes')
    other,_=prefix(jobs[1]['genesis'][297:])
    refusal('recommitted-wrong-pre',first['genesis'],[raw_state(other)+block+after],'ImportFailure',0,'PreStateMismatch')
    damaged=bytearray(first['steps'][1]);_,start=prefix(bytes(damaged));_,_,children=block_oracle.parse('B',bytes(damaged[start:]),config)
    damaged[start+len(children[0])-1]^=1
    refusal('later-seal-failure',first['genesis'],[first['steps'][0],bytes(damaged)],'ImportFailure',1,'CandidateFailure')
    metadata=[dict(label=j['label'],config_sha256=hashlib.sha256(j['config'].encode()).hexdigest(),
        genesis_sha256=hashlib.sha256(j['genesis']).hexdigest(),steps_sha256=[hashlib.sha256(step).hexdigest() for step in j['steps']],expected=answer)
        for j,answer in zip(jobs,answers)]
    evidence=dict(transitions=sum(len(row) for row in roots),chains=len(roots),cases=len(jobs),roots=roots,
        checkpoint_sha256=hashes,origins=origins,refusals=answers[len(roots):],jobs=metadata)
    if check_frozen:validate_frozen(FIXTURE,SOURCES,evidence)
    return jobs,answers,evidence
