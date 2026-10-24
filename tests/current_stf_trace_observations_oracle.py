# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete observed-map test doubles verify native differential plumbing without claiming external-client execution."""
import copy
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
import current_stf_trace_command_oracle as source
import state_trace_wire_oracle as raw
import block_oracle

FIXTURE=Path(__file__).parent/'fixtures/current-stf-trace-observations.json'


def post_state(step):
    """Extract only an independently calculated expected posterior RawState; no native result supplies a test observation."""
    _,first=raw.prefix(step);length,_,_=block_oracle.parse('B',step[first:],block_oracle.TINY)
    wire=step[first+length:];_,consumed=raw.prefix(wire);assert consumed==len(wire)
    return wire


def expected_observations(check_frozen=True):
    """Freeze correct/wrong-map observation test doubles and exact command outcomes before native differential execution."""
    originals,answers,evidence=source.expected_observations()
    jobs=copy.deepcopy(originals[:40]);expected=answers[:40]
    for job in jobs:
        job['observations']=[post_state(step) for step in job['steps']] # These are explicitly mathematical test doubles, not independent client output.
    first=jobs[0];before,_=raw.prefix(first['steps'][0]);wrong=raw.wire(before);correct=first['observations'][0]
    def refusal(steps,observations,error,checked,detail):
        """A failed external comparison cannot bypass the original expected transition or release a final successful root."""
        job=copy.deepcopy(first);job['steps']=steps;job['observations']=observations;jobs.append(job)
        expected.append('C '+error+' '+str(checked)+' '+detail)
    refusal(first['steps'][:1],[None],'ObservationFailure',0,'IoFailure')
    refusal(first['steps'][:1],[bytes([correct[0]^1])+correct[1:]],'ObservationFailure',0,'RootMismatch')
    refusal(first['steps'][:1],[correct+b'\0'],'ObservationFailure',0,'TrailingBytes')
    refusal(first['steps'][:1],[wrong],'ImportFailure',0,'ObservationMismatch')
    refusal(first['steps'][:2],[correct,wrong],'ImportFailure',1,'ObservationMismatch')
    refusal(originals[-4]['steps'],[correct],'ImportFailure',0,'PostStateMismatch')
    refusal(originals[-1]['steps'],first['observations'][:2],'ImportFailure',1,'CandidateFailure')
    traces=dict(source_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest(),observation_origin='independent mathematical test doubles; no external engine execution',
        jobs=[dict(config_sha256=hashlib.sha256(j['config'].encode()).hexdigest(),genesis_sha256=hashlib.sha256(j['genesis']).hexdigest(),
            steps_sha256=[hashlib.sha256(w).hexdigest() for w in j['steps']],
            observations_sha256=[None if w is None else hashlib.sha256(w).hexdigest() for w in j['observations']],expected=answer) for j,answer in zip(jobs,expected)])
    result=dict(transitions=evidence['transitions'],chains=evidence['chains'],roots=evidence['roots'],checkpoint_sha256=evidence['checkpoint_sha256'],traces=traces,cases=len(jobs),rejected_jobs=7)
    if check_frozen:
        frozen=json.loads(FIXTURE.read_text());assert frozen['successor_roots']==result['roots'] and frozen['successor_checkpoint_sha256']==result['checkpoint_sha256'] and frozen['traces']==traces
    return jobs,expected,result
