# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent published trace inputs drive actual authenticated current STF import and whole-map matching."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
import current_stf_interchange_oracle as current
from current_stf_oracle import decode_checkpoint
from state_trace_wire_oracle import wire

FIXTURE=Path(__file__).parent/'fixtures/current-stf-trace-import.json'


def expected_observations(check_frozen=True):
    """Supply already-signed independent blocks/maps; native preparation cannot replace their advertised answers."""
    commands,expected,evidence=current.expected_observations()
    modes=iter(line.removesuffix(' exchange')+' trace' for line in commands if line.startswith('C '))
    requests=[];lines=[];parent=None;block=None
    for line in expected:
        if line.startswith('P '):
            requests.append(next(modes));parent=decode_checkpoint(bytes.fromhex(line[2:]))
        elif line.startswith('B '):
            block=bytes.fromhex(line[2:]) # Exact independent sealed headers and bodies enter the importer without native re-signing.
        elif line.startswith('O '):
            after=decode_checkpoint(bytes.fromhex(line[2:]));trace=wire(list(parent.items()))+block+wire(list(after.items()))
            requests.append('T '+trace.hex());parent=after # Recursion uses the independently calculated successor only.
        lines.append(line)
        if line.startswith('B '):
            lines.extend(('R PreStateMismatch','R PostStateMismatch','R CandidateFailure')) # Recommitted wrong pre/post maps and an altered seal must never grant an installable update.
    traces=dict(source_sha256=hashlib.sha256(current.FIXTURE.read_bytes()).hexdigest(),families=evidence['traces'],pre_state_refusals=255,post_state_refusals=255,seal_refusals=255)
    result=dict(transitions=evidence['transitions'],chains=evidence['chains'],roots=evidence['roots'],checkpoint_sha256=evidence['checkpoint_sha256'],traces=traces,refusals=765)
    if check_frozen:
        frozen=json.loads(FIXTURE.read_text());assert frozen['successor_roots']==result['roots'] and frozen['successor_checkpoint_sha256']==result['checkpoint_sha256'] and frozen['traces']==traces
    return requests,lines,result
