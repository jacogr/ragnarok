# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Transport pinned history STF bytes and independent output-tree checks to native assertions.

Exposes prepare and fixture construction helpers that write trusted inputs for native tests.
"""
import hashlib
import json
import subprocess
from test_support import ROOT
from state_history_oracle import wire
from test_crypto import keccak256


# Preserve published C(3) data with canonical dictionary key order and exact optional peak tags.
def state_bytes(beta):
    blocks = []
    for record in beta['history']:
        # T orders header, super-peak, state root, slot and dictionary, unlike the conceptual tuple.
        fixed = b''.join(bytes.fromhex(record[key][2:]) for key in ('header_hash', 'beefy_root', 'state_root'))
        fixed += record['slot'].to_bytes(4, 'little')
        pairs = sorted((bytes.fromhex(p['hash'][2:]), bytes.fromhex(p['exports_root'][2:])) for p in record['reported'])
        blocks.append((fixed, b''.join(k+v for k,v in pairs)))
    peaks = [None if p is None else bytes.fromhex(p[2:]) for p in beta['mmr']['peaks']]
    return wire((blocks, peaks)).hex()


# Direct appendix equations independently cover raw 36-byte leaves and uneven well-balanced splits.
def output_root(values):
    def node(items):
        # N(empty) is zero; N(single) preserves its original blob.
        if not items:
            return bytes(32)
        if len(items) == 1:
            return items[0]
        half = (len(items)+1)//2
        return bytes.fromhex(keccak256(b'node'+node(items[:half])+node(items[half:])))
    # The well-balanced wrapper hashes only a singleton root leaf.
    return bytes.fromhex(keccak256(values[0])) if len(values) == 1 else node(values)


# Require exact source pins before emitting ignored fixtures and their provenance manifest.
def prepare(folder):
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    lines, sources = [], []
    for profile in ('tiny', 'full'):
        for number in range(1, 5):
            # All eight published history cases are required, without deriving expected transitions.
            name = f'stf/history/{profile}/progress_blocks_history-{number}.json'
            raw = subprocess.check_output(['git', '-C', str(ROOT/pins['path']), 'show', pins['commit']+':'+name])
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == pins['git_blobs'][name]
            case = json.loads(raw)
            assert case['output'] is None
            inp = case['input']
            packages = inp['work_packages']
            lines.append(' '.join([str(2 if profile == 'tiny' else 341), str(inp['slot']),
                inp['header_hash'][2:], inp['parent_state_root'][2:], inp['accumulate_root'][2:], str(len(packages))]+
                [p[key][2:] for p in packages for key in ('hash', 'exports_root')]))
            lines.extend((state_bytes(case['pre_state']['beta']), state_bytes(case['post_state']['beta'])))
            sources.append(dict(path=name, sha256=digest))
    # Deterministic independent tree roots include zero, singleton, powers and uneven splits.
    for count in (0, 1, 2, 3, 4, 5, 7, 8, 9, 17, 128):
        values = [((2**32-1-i).to_bytes(4, 'little')+hashlib.sha256(bytes([i])).digest()) for i in range(count)]
        lines.append(str(count)+' '+output_root(values).hex()+' '+b''.join(values).hex())
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'history-transition.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(cases=len(sources), tree_cases=11, sources=sources, vector_commit=pins['commit'],
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'history-transition.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
