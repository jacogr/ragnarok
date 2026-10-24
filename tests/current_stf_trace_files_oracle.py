# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-map STF files retain exact signed inputs through bounded regular-file ingress."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
import current_stf_trace_import_oracle as source

FIXTURE=Path(__file__).parent/'fixtures/current-stf-trace-files.json'


def expected_observations(check_frozen=True):
    """Freeze logical file contents before orchestration assigns private absolute filenames; native output never determines input bytes."""
    requests,lines,evidence=source.expected_observations()
    requests=[line.removesuffix(' trace')+' trace-file' if line.startswith('C ') else line for line in requests]
    hashes=[hashlib.sha256(bytes.fromhex(line[2:])).hexdigest() for line in requests if line.startswith('T ')]
    traces=dict(source_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest(),file_sha256=hashes,refusals=evidence['refusals'])
    result=dict(transitions=evidence['transitions'],chains=evidence['chains'],roots=evidence['roots'],checkpoint_sha256=evidence['checkpoint_sha256'],traces=traces,files=len(hashes),refusals=evidence['refusals'])
    if check_frozen:
        frozen=json.loads(FIXTURE.read_text());assert frozen['successor_roots']==result['roots'] and frozen['successor_checkpoint_sha256']==result['checkpoint_sha256'] and frozen['traces']==traces
    return requests,lines,result
