# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map accseq cases for queued incoming credits and supervisor incarnations."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-supervised-transfers.json'
PROFILES = ('unsupervised', 'active-supervisor', 'stale-supervisor', 'missing-supervisor', 'self-supervisor')


def original(profile):
    """Only the recipient's declared supervisor identity/incarnation changes from the prior funded transfer original."""
    parent = transfers.original('halt')
    key = chapter_service(255, 42)
    code, wide, narrow = account_parse(parent[key], 105)
    narrow = list(narrow)
    narrow[4] = {'unsupervised': 0, 'active-supervisor': 99, 'stale-supervisor': 99,
                 'missing-supervisor': 77, 'self-supervisor': 42}[profile]
    narrow[5] = 1 if profile == 'stale-supervisor' else 0
    parent[key] = account_wire((code, wide, narrow))
    return parent


def effects(result, profile, slot, *, statistics_config=DEFAULT):
    """Two affordable actual-gas continuation rounds emit two credits; active supervisor99 alone holds both for one recipient invocation."""
    assert 200000 <= 300000 < 400000
    assert 200000+10000 <= 300000-10678+10000
    transfers.effects(result,'halt',slot,statistics_config=statistics_config)
    transfers.effects(result,'halt',slot,statistics_config=statistics_config)
    held=profile=='active-supervisor'
    if held:
        (current,previous,cores,services),_=statistics_parse(result[chapter_key(13)],statistics_config)
        services=[tuple(list(row[:11])+[22]) if row[0]==42 else row for row in services]
        result[chapter_key(13)]=statistics_wire((current,previous,cores,services))
    return dict(slot=slot,report_rounds=2,recipient_invocations=1 if held else 2,
                recipient_transfers=2,held_while_active=held)


def expected_observations(check_frozen=True):
    """Two200000-gas reports force separate source rounds; accepted inputs either join or wait for that active supervisor."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}
        requests.append('C '+str(index+10)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 6):
            gs = [pipeline.guarantee(parent, initial, core, slot, service=99, accumulation_gas=200000)
                  for core in range(2)] if slot == 3 else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']
            ass = assurances(parent, 5 if slot == 4 else 0, 3)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot == 4 else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released)==2
                traces[-1].append(effects(result,profile,slot))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
    return requests, lines, dict(transitions=20, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
