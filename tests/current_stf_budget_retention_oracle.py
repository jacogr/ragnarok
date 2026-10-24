# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-map deferred retention and drain across exact actual-budget boundaries."""
import hashlib
import json
from pathlib import Path
import current_stf_dependency_waves_oracle as waves
from current_stf_oracle import checkpoint, tree
from current_stf_reporting_oracle import body

FIXTURE = Path(__file__).parent/'fixtures/current-stf-budget-retention.json'
PROFILES = ('serial', 'exact-residual-fit', 'one-above-residual')
CASES = [(mode, profile) for mode in waves.pipeline.MODES for profile in PROFILES]


def gas_limits(profile):
    """A costs22 actual gas: B's declared299978 fits the residual, while299979 cannot."""
    limits = dict.fromkeys('ABCDE', 300000)
    if profile != 'serial': limits['B'] = 299978 if profile == 'exact-residual-fit' else 299979
    return limits


def expected_observations(check_frozen=True):
    """Calculate all150 signed children/maps and retention traces before running the shared native driver."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['base_fixture_sha256'] == hashlib.sha256(waves.FIXTURE.read_bytes()).hexdigest()
    requests, lines, roots, hashes, plans = [], [], [], [], []
    invocations = processed_count = 0
    for mode, profile in CASES:
        initial = waves.pipeline.original(mode); parent = dict(initial); reports = {}
        roots.append([]); hashes.append([]); plans.append([])
        requests.append('C '+str(waves.pipeline.MODES.index(mode)))
        lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in range(2, 12):
            gs, ass = waves.inputs(parent, initial, slot, False, reports, gas_limits=gas_limits(profile))
            projection = waves.plan(parent, mode, slot, ass, reports)
            child, parent = waves.pipeline.advance(parent, initial, mode, slot, gs, ass, plan=projection)
            encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex())
            hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            plans[-1].append({key: projection[key] for key in ('waves', 'prefixes', 'remaining_gas')})
            invocations += sum(len(group) for group in projection['batches'])
            processed_count += len(projection['processed'])
    if check_frozen:
        assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
        assert plans == fixture['plans']
    return requests, lines, dict(transitions=150, chains=15, guest_executions=invocations,
                                processed_reports=processed_count, roots=roots,
                                checkpoint_sha256=hashes, plans=plans)
