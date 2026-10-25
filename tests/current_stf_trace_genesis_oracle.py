# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independently authored published Genesis files and externally anchored current STF replay."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
import current_stf_trace_import_oracle as source
from current_stf_oracle import decode_checkpoint
from state_trace_wire_oracle import wire
from state_layout_oracle import digest

FIXTURE=Path(__file__).parent/'fixtures/current-stf-trace-genesis.json'
BINARY=FIXTURE.with_suffix('.bin')


def initial_header():
    """Author the maintained slot1 seed from explicit fields, without reading a native header observation."""
    ancient=bytes(297)
    return digest(ancient)+bytes(64)+(1).to_bytes(4,'little')+bytes(2)+bytes(96)+bytes(3)+bytes(96)


def expected_observations(check_frozen=True):
    """Freeze independent Genesis header/maps, exact child blocks, complete successors and all refusal observations before execution."""
    commands,expected,evidence=source.expected_observations()
    modes=iter(line.removesuffix(' trace')+' trace-genesis' for line in commands if line.startswith('C '))
    inputs=iter(line for line in commands if line.startswith('T '))
    requests=[];lines=[];genesis=[];first_block=False;header=initial_header()
    assert len(header)==297
    for line in expected:
        if line.startswith('P '):
            parent=decode_checkpoint(bytes.fromhex(line[2:]));raw=header+wire(list(parent.items()))
            requests.extend((next(modes),'G '+raw.hex()));first_block=True
            lines.extend((line,'G '+raw.hex(),'A HeaderMismatch','A StateMismatch','A InvalidParameters'))
            genesis.append(dict(header_hash=digest(header).hex(),state_root=raw[297:329].hex(),wire_sha256=hashlib.sha256(raw).hexdigest()))
            continue # New input owners are compared before the unchanged independently signed children.
        if line.startswith('B ') and first_block:
            assert bytes.fromhex(line[2:])[:32]==digest(header) # Independently signed children bind this exact authored original header.
            first_block=False
        if line.startswith('O '):
            requests.append(next(inputs)) # Full signed TraceStep input remains exactly the independent predecessor/successor pair.
        lines.append(line)
    traces=dict(source_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest(),genesis=genesis,bootstrap_refusals=120,transition_refusals=evidence['refusals'])
    result=dict(transitions=evidence['transitions'],chains=evidence['chains'],roots=evidence['roots'],checkpoint_sha256=evidence['checkpoint_sha256'],traces=traces,refusals=885)
    if check_frozen:
        frozen=json.loads(FIXTURE.read_text());assert frozen['successor_roots']==result['roots'] and frozen['successor_checkpoint_sha256']==result['checkpoint_sha256'] and frozen['traces']==traces
        assert BINARY.read_bytes()==bytes.fromhex(next(line[2:] for line in requests if line.startswith('G ')))
    return requests,lines,result
