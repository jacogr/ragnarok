# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""GP-consistent independently calculated preimage expiry and report lookup-age cases."""
import hashlib
import json
from pathlib import Path
import current_stf_preimage_aging_oracle as source
from current_stf_oracle import checkpoint, tree
from current_stf_reporting_oracle import assurances
from state_layout_oracle import chapter_key

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-parameter-aging.json'
LOOKUP_AGE = 14400
SLOTS = (2, 19197, 19198, 19199, 19201, 19202, 19203)


def expected_observations(check_frozen=True):
    """Use recent proved lookup anchors while testing strict age14400+4800 at equality and two slots later."""
    source.expected_observations() # Preserve the unchanged historical zero-age reference as separate evidence.
    lines, roots, traces = [], [], []
    pipeline = source.transfers.pipeline
    for profile in source.PROFILES:
        parent = source.original(profile)
        initial = dict(parent)
        reports, budgets = {}, {}
        lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([])
        traces.append([])
        for slot in SLOTS:
            budget = 100000
            gs = [pipeline.guarantee(parent, parent, 1, slot, service=99, accumulation_gas=budget)] if slot in (19199, 19202) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']
                budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot in (19201, 19203) else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (19201, 19203) else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)],
                        reports=reports, yielded=False, foundation=source.foundation(parent, slot))
            wire, posterior = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released) == 1
                traces[-1].append(source.effects(posterior, parent, profile, slot,
                                                 budgets[released[0][:32]], lookup_age=LOOKUP_AGE))
            lines.extend(('B '+wire.hex(), 'O '+checkpoint(list(posterior.items())).hex()))
            roots[-1].append(tree(list(posterior.items()))[0].hex())
            parent = posterior
    evidence = dict(graypaper_commit='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d',
                    base_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest(),
                    lookup_age=LOOKUP_AGE, expunge_period=LOOKUP_AGE+4800,
                    transitions=35, chains=5, roots=roots, traces=traces,
                    expected_sha256=hashlib.sha256(('\n'.join(lines)+'\n').encode()).hexdigest())
    if check_frozen:
        assert json.loads(FIXTURE.read_text()) == json.loads(json.dumps(evidence))
    return [], lines, evidence
