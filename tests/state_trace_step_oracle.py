# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent published TraceStep composition over frozen complete STF maps and real signed blocks."""
import hashlib
import json
from pathlib import Path
import block_oracle
import state_trace_wire_oracle as raw
from current_stf_oracle import decode_checkpoint, checkpoint

FIXTURE=Path(__file__).parent/'fixtures/state-trace-step.json'
BINARY=FIXTURE.with_suffix('.bin')


def expected_observations(check_frozen=True):
    """Calculate every composed wire and exact pre/block/post field before invoking native composition."""
    requests=[];expected=[];proof=[];sources={};first=None
    def accepted(before,body,after,label,tail=b''):
        """The published schema concatenates its three self-delimiting fields, with no invented lengths or magic."""
        nonlocal first
        wire=raw.wire(before)+body+raw.wire(after)
        if first is None:
            first=wire # A separately frozen authored transition supplies the native ownership unit's input.
        requests.append(str(raw.MAX)+' '+(wire+tail).hex())
        expected.append('S '+str(len(wire))+' '+wire.hex()+' '+checkpoint(before).hex()+' '+body.hex()+' '+checkpoint(after).hex())
        proof.append(dict(label=label,wire_sha256=hashlib.sha256(wire).hexdigest(),pre_root=raw.tree(before)[0].hex(),post_root=raw.tree(after)[0].hex(),block_sha256=hashlib.sha256(body).hexdigest()))
        return wire
    def refused(wire,reason,limit=raw.MAX):
        """Each malformed field has an independently selected failing stage; no successful prefix is expected."""
        requests.append(str(limit)+' '+wire.hex());expected.append('E '+reason)
    _,lines,_=raw.current.expected_observations();before=None;body=None
    for line in lines:
        if line.startswith('P '):
            before=list(decode_checkpoint(bytes.fromhex(line[2:])).items())
        elif line.startswith('B '):
            body=bytes.fromhex(line[2:])
        elif line.startswith('O '):
            after=list(decode_checkpoint(bytes.fromhex(line[2:])).items())
            accepted(before,body,after,'current',b'next-field');before=after # Only independently calculated successors become the next reference pre-state.
    for path in ('traces/fallback/00000001','traces/storage/00000001','traces/preimages/00000001'):
        wire=raw.published(path+'.bin');data=json.loads(raw.published(path+'.json'))
        before,extent=raw.prefix(wire);parsed=block_oracle.parse('B',wire[extent:],block_oracle.TINY)
        assert not isinstance(parsed,str),parsed
        length,_,_=parsed;body=wire[extent:extent+length];after,post=raw.prefix(wire[extent+length:])
        assert extent+length+post==len(wire)
        for pairs,phase in ((before,'pre_state'),(after,'post_state')):
            assert pairs==[(bytes.fromhex(item['key'][2:]),bytes.fromhex(item['value'][2:])) for item in data[phase]['keyvals']]
        assert accepted(before,body,after,path)==wire
        sources[path+'.bin']=hashlib.sha256(wire).hexdigest()
    assert first is not None
    before,extent=raw.prefix(first);length,_,_=block_oracle.parse('B',first[extent:],block_oracle.TINY)
    bad=bytes([first[0]^1])+first[1:];refused(bad,'PreStateFailure RootMismatch')
    at=extent+length;bad=first[:at]+bytes([first[at]^1])+first[at+1:];refused(bad,'PostStateFailure RootMismatch')
    refused(first[:10],'PreStateFailure Truncated')
    refused(first[:extent+1],'BlockFailure InvalidComponent')
    refused(first[:at+10],'PostStateFailure Truncated')
    refused(first,'PostStateFailure LimitExceeded',len(first)-1)
    evidence=dict(cases=len(requests),accepted=len(proof),refused=len(requests)-len(proof),sources=sources,proof=proof,unit_wire_sha256=hashlib.sha256(first).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text())==evidence and BINARY.read_bytes()==first
    return requests,expected,evidence
