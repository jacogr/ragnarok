# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent operator bundles retain published Genesis/TraceStep bytes, full configured Parameters and whole-map answers."""
import copy
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
import current_stf_trace_genesis_oracle as source
import state_trace_wire_oracle as raw
import block_oracle

FIXTURE=Path(__file__).parent/'fixtures/current-stf-trace-command.json'


def parameters(mode):
    """Author the exact independently configured122-byte tuple; do not call native parameter encoding or infer values from state roots."""
    wire=bytearray([255]*122)
    for offset,width,value in ((24,2,2),(30,4,12),(82,2,80),(98,4,512),(118,4,12),(110,4,128)):
        wire[offset:offset+width]=value.to_bytes(width,'little')
    wire[:24]=bytes(24)
    if 176<=mode<=189:
        wire[:24]=b''.join(value.to_bytes(8,'little') for value in (7,1,100))
    return bytes(wire)


def chain_config(genesis,profile):
    """Use the existing strict configured-chain JSON representation, with independent header/state anchors and the entire parameter tuple."""
    pairs,consumed=raw.prefix(genesis[297:]);assert consumed+297==len(genesis)
    return json.dumps(dict(protocol_parameters=profile.hex(),genesis_header=genesis[:297].hex(),
        genesis_state={key.hex():value.hex() for key,value in pairs}),indent=2,sort_keys=True)+'\n'


def expected_observations(check_frozen=True):
    """Calculate all exact files and complete-map outcomes before native policy-input materialization and execution."""
    commands,_,evidence=source.expected_observations();jobs=[]
    for line in commands:
        if line.startswith('C '):
            mode=int(line.split()[1]);jobs.append(dict(mode=mode,genesis=b'',steps=[]))
        elif line.startswith('G '):
            jobs[-1]['genesis']=bytes.fromhex(line[2:])
        else:
            assert line.startswith('T ');jobs[-1]['steps'].append(bytes.fromhex(line[2:])) # Exact independently signed wires stay unchanged.
    expected=[]
    for job,roots in zip(jobs,evidence['roots']):
        job['config']=chain_config(job['genesis'],parameters(job['mode']))
        expected.append('C None '+str(len(job['steps']))+' '+roots[-1])
    first=jobs[0];before,extent=raw.prefix(first['steps'][0])
    length,_,parts=block_oracle.parse('B',first['steps'][0][extent:],block_oracle.TINY)
    block=first['steps'][0][extent:extent+length];after=first['steps'][0][extent+length:]
    def refusal(genesis,steps,error,checked,detail=''):
        """A separate rejected invocation cannot publish a successful final root or change its configured files."""
        job=copy.deepcopy(first);job['genesis']=genesis;job['steps']=steps;jobs.append(job)
        expected.append('C '+error+' '+str(checked)+' '+(detail or '-'))
    refusal(jobs[1]['genesis'],first['steps'][:1],'BootstrapFailure',0,'StateMismatch')
    refusal(first['genesis']+b'\0',first['steps'][:1],'TrailingGenesis',0)
    refusal(first['genesis'],[raw.wire(before)+block+raw.wire(before)],'ImportFailure',0,'PostStateMismatch')
    refusal(first['genesis'],[first['steps'][0]+b'\0'],'TraceFailure',0,'TrailingBytes')
    other,_=raw.prefix(jobs[1]['genesis'][297:])
    refusal(first['genesis'],[raw.wire(other)+block+after],'ImportFailure',0,'PreStateMismatch')
    damaged=bytearray(first['steps'][1]);_,start=raw.prefix(bytes(damaged))
    _,_,children=block_oracle.parse('B',bytes(damaged[start:]),block_oracle.TINY)
    damaged[start+len(children[0])-1]^=1
    refusal(first['genesis'],[first['steps'][0],bytes(damaged)],'ImportFailure',1,'CandidateFailure')
    traces=dict(source_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest(),
        jobs=[dict(mode=j['mode'],parameters_sha256=hashlib.sha256(parameters(j['mode'])).hexdigest(),
            config_sha256=hashlib.sha256(j['config'].encode()).hexdigest(),genesis_sha256=hashlib.sha256(j['genesis']).hexdigest(),
            steps_sha256=[hashlib.sha256(step).hexdigest() for step in j['steps']],expected=answer) for j,answer in zip(jobs,expected)])
    result=dict(transitions=evidence['transitions'],chains=evidence['chains'],roots=evidence['roots'],
        checkpoint_sha256=evidence['checkpoint_sha256'],traces=traces,cases=len(jobs),rejected_jobs=6)
    if check_frozen:
        frozen=json.loads(FIXTURE.read_text());assert frozen['successor_roots']==result['roots'] and frozen['successor_checkpoint_sha256']==result['checkpoint_sha256'] and frozen['traces']==traces
    return jobs,expected,result
