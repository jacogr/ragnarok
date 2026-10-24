# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full maps for skipped-slot ready expiry after actual affordable execution."""
import hashlib
import json
from pathlib import Path
import current_stf_epoch_drain_oracle as epoch_drain
from current_stf_oracle import checkpoint, tree
from current_stf_reporting_oracle import body, ready
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/current-stf-ready-expiry.json'
PROFILES = ('expiry-boundary', 'past-expiry', 'full-ring-skip')
CASES = [(mode, profile) for mode in epoch_drain.waves.pipeline.MODES for profile in PROFILES]


def slots(profile):
    """All inputs are reachable through11; the first later block crosses one epoch with9,10 or12 elapsed slots."""
    jump = {'expiry-boundary': 20, 'past-expiry': 21, 'full-ring-skip': 23}[profile]
    return list(range(2, 12))+list(range(jump, 25))


def expected_observations(check_frozen=True):
    """Calculate205 signed children/full maps, processing prefixes and discarded package sets before native execution."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['base_fixture_sha256'] == hashlib.sha256(epoch_drain.FIXTURE.read_bytes()).hexdigest()
    requests, lines, roots, hashes, traces = [], [], [], [], []
    processed_count = 0
    for mode, profile in CASES:
        initial = epoch_drain.waves.pipeline.original(mode); parent = dict(initial); reports = {}
        roots.append([]); hashes.append([]); traces.append([])
        requests.append('C '+str(epoch_drain.waves.pipeline.MODES.index(mode)))
        lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in slots(profile):
            gs, ass = epoch_drain.inputs(parent, slot, reports)
            projection = epoch_drain.waves.plan(parent, mode, slot, ass, reports)
            before = {wire[:32] for row in ready(parent[chapter_key(14)]) for wire, _ in row}
            retained = {wire[:32] for row in projection['ready'] for wire, _ in row}
            processed = {wire[:32] for wire in projection['processed']}
            projection['foundation'] = epoch_drain.foundation(parent, slot)
            child, parent = epoch_drain.waves.pipeline.advance(parent, initial, mode, slot, gs, ass, plan=projection)
            encoded = checkpoint(list(parent.items()))
            requests.append('B '+str(slot)+' '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            traces[-1].append(dict(slot=slot, processed=sorted(key.hex() for key in processed),
                                   expired=sorted(key.hex() for key in before-retained-processed),
                                   prefixes=projection['prefixes']))
            processed_count += len(projection['processed'])
    if check_frozen:
        assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
        assert traces == fixture['traces']
    return requests, lines, dict(transitions=205, chains=15, processed_reports=processed_count,
                                roots=roots, checkpoint_sha256=hashes, traces=traces)
