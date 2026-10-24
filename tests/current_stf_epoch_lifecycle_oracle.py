# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent request/provision lifecycle composition with epoch rotation, validator statistics and signed boundary markers."""
import hashlib
import json
from pathlib import Path
from current_stf_preimage_provision_oracle import original, effects, PROFILES, transfers
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key
import current_stf_epoch_oracle as epoch

FIXTURE = Path(__file__).parent/'fixtures/current-stf-epoch-lifecycle.json'


def foundation(parent, slot):
    """Uniform pinned rosters need no ticket proofs; exact C7 membership retains the committed pending root on rotation."""
    pending, root, _, _, _ = epoch.consensus(parent[chapter_key(4)])
    assert pending == epoch.roster(parent[chapter_key(7)])
    def advance(raw, commitment, outputs):
        """Independently derive markers, Thin seals, rotated entropy/rosters and statistics before report/guest effects."""
        return epoch.successor(parent, slot, [], [], {'staging': root}, body_override=raw,
                               extrinsic_override=commitment, outputs=outputs)
    return advance


def expected_observations(check_frozen=True):
    """Calculate thirty full transitions with provision releases on either side of the epoch boundary."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+67)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in (8, 9, 10, 11, 12, 13):
            budget = 100000
            gs = [pipeline.guarantee(parent, parent, 1, slot, service=99, accumulation_gas=budget)] if slot in (9, 11) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot in (10, 12) else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (10, 12) else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            plan['foundation'] = foundation(parent, slot)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released) == 1
                traces[-1].append(effects(result, parent, profile, slot, budgets[released[0][:32]]))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+str(slot)+' '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
    return requests, lines, dict(transitions=30, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
