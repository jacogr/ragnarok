# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport pinned authorization STF inputs/expected bytes to native assertions; no transition logic here.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from pathlib import Path
from test_support import ROOT


# Preserve fixed hash octets and the canonical one-byte pool counts (0..8) independently of native codecs.
def wire(rows, pools):
    result = bytearray()
    for row in rows:
        # Pools carry a bounded natural prefix; queues are fixed 80-element sequences without a prefix.
        assert (0 <= len(row) <= 8) if pools else len(row) == 80
        if pools:
            result.append(len(row))
        for item in row:
            # No reordering, duplicate removal or source-value replacement is permitted.
            assert item.startswith('0x')
            raw = bytes.fromhex(item[2:])
            assert len(raw) == 32
            result.extend(raw)
    return result.hex()


# Validate every consumed immutable blob against the recorded pin before creating any native fixture.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    lines, sources = [], []
    for profile in ('tiny', 'full'):
        for number in (1, 2, 3):
            # These are the complete published authorization STF family at this revision.
            name = f'stf/authorizations/{profile}/progress_authorizations-{number}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+name])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][name], name
            case = json.loads(raw)
            before, after, inputs = case['pre_state'], case['post_state'], case['input']
            cores = len(before['auth_pools'])
            assert cores == (2 if profile == 'tiny' else 341)
            assert len(before['auth_queues']) == len(after['auth_pools']) == len(after['auth_queues']) == cores
            assert case['output'] is None and before['auth_queues'] == after['auth_queues']
            uses = inputs['auths']
            lines.append(f'{cores} {inputs["slot"]} {len(uses)}'+
                         ''.join(' '+str(use['core'])+' '+use['auth_hash'][2:] for use in uses))
            lines.extend((wire(before['auth_pools'], True), wire(before['auth_queues'], False),
                          wire(after['auth_pools'], True)))
            sources.append(dict(path=name, sha256=digest, profile=profile, cores=cores,
                                slot=inputs['slot'], uses=len(uses)))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'authorization-transition.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(cases=len(sources), sources=sources,
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                    vector_commit=pins['commit'])
    (folder/'authorization-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
