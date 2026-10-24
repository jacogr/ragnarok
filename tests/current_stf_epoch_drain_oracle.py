# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-map epoch-spanning retained report execution with exact signed marker bodies."""
import hashlib
import json
from pathlib import Path
import current_stf_dependency_waves_oracle as waves
import current_stf_epoch_oracle as epoch
from current_stf_reporting_oracle import body
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/current-stf-epoch-drain.json'


def inputs(parent, slot, reports, *, blocked=False):
    """Admit the earlier reachable graph four slots later, anchoring honestly to each actual recent parent."""
    logical = slot-4
    if logical < 2: return [], []
    gas = dict.fromkeys('ABCDE', 300000)
    if blocked: gas['B'] = 300001
    return delayed(parent, slot, logical, reports, gas)


def delayed(parent, slot, logical, reports, gas):
    """Author report context at actual time; only the graph's schedule is translated, never credential rotation."""
    specifications = []
    if logical == 3: specifications = [('A', 0, 42, [], []), ('B', 1, 99, ['A'], [])]
    elif logical in (4, 5, 6):
        specifications = {4: [('C', 1, 99, ['A', 'B'], [])], 5: [('D', 1, 99, [], ['C'])],
                          6: [('E', 1, 99, ['B', 'D'], ['B'])]}[logical]
    gs = []
    for name, core, sid, dependencies, lookups in specifications:
        lookup = b''.join(waves.package(key)+waves.digest(waves.package(key)+b'exports') for key in sorted(lookups, key=waves.package))
        item = waves.pipeline.guarantee(parent, parent, core, slot, service=sid, package=waves.package(name),
                  prerequisites=b''.join(sorted(waves.package(key) for key in dependencies)), lookup=lookup,
                  accumulation_gas=gas[name])
        reports[item['report'][:32]] = item['layout']; gs.append(item)
    count, bits = (5, 2) if logical in (4, 5, 6) else ((5, 3) if logical == 7 else (0, 0))
    return gs, waves.assurances(parent, count, bits)


def foundation(parent, slot):
    """Retain the qualified original ring witness while independently calculating all epoch/global effects."""
    pending, root, *_ = epoch.consensus(parent[chapter_key(4)])
    assert pending == epoch.roster(parent[chapter_key(7)])
    def calculate(raw, commitment, outputs):
        """Literal full bodies and terminal outputs feed the existing mathematical Safrole/header equations."""
        return epoch.successor(parent, slot, [], [], dict(staging=root), body_override=raw,
                               extrinsic_override=commitment, outputs=outputs)
    return calculate


def expected_observations(check_frozen=True):
    """Calculate75 complete transitions, including four guest blocks in the new epoch, before native execution."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['base_fixture_sha256'] == hashlib.sha256(waves.FIXTURE.read_bytes()).hexdigest()
    requests, lines, roots, hashes = [], [], [], []
    for mode in waves.pipeline.MODES:
        initial = waves.pipeline.original(mode); parent = dict(initial); reports = {}
        roots.append([]); hashes.append([])
        requests.append('C '+str(waves.pipeline.MODES.index(mode))); lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in range(2, 17):
            gs, ass = inputs(parent, slot, reports)
            projection = waves.plan(parent, mode, slot, ass, reports)
            projection['foundation'] = foundation(parent, slot)
            child, parent = waves.pipeline.advance(parent, initial, mode, slot, gs, ass, plan=projection)
            encoded = checkpoint(list(parent.items()))
            requests.append('B '+str(slot)+' '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen: assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
    return requests, lines, dict(transitions=75, chains=5, processed_reports=25, roots=roots, checkpoint_sha256=hashes)
