# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prepare trusted native storage replay inputs from exact already-pinned published mapping blobs.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
from state_roots_oracle import published, TRACE_PATHS


# Preparation preserves every key/value/root; native assertions own all store and mutation verdicts.
def prepare(folder):
    observations = published()
    assert len(observations) == 2*len(TRACE_PATHS)
    lines = []
    records = []
    for entries, source in observations:
        # Empty values retain a real token; no projection, typed reconstruction or field repair is performed.
        lines.append(source['state_root']+' '+str(source['nodes'])+' '+str(len(entries))+
                     ''.join(' '+key.hex()+' '+(value.hex() if value else '-') for key, value in entries))
        records.append(source)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'state-store-replay.txt'
    path.write_text('\n'.join(lines)+'\n')
    metadata = dict(pairs=len(TRACE_PATHS), mappings=len(observations), sources=records,
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'state-store-replay.json').write_text(json.dumps(metadata, indent=2)+'\n')
    return path, metadata
