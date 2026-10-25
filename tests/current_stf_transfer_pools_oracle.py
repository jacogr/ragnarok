# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole maps for all source/destination balance pools and direct versus deferred credit."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_effects_oracle import immediate, envelope, simulate, gas_definitions
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-transfer-pools.json'
PROFILES = [(direct, selection) for direct in (False, True) for selection in range(4)]


def program(direct, selection):
    """Literal flags choose the two independent pools; zero memo selects immediate atomic credit."""
    instructions = [immediate(7, 2**64-1), immediate(8, 42), immediate(9, selection), immediate(10, 7),
                    immediate(11, 10000), immediate(12, 0 if direct else 196608), bytes([10, 22]), bytes([50, 0])]
    return instructions, bytes(128)


def original(direct, selection):
    """Fund exactly the chosen source pool, reserving honest code bytes and direct-destination authority."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory = program(direct, selection)
    raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw
    parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old)
    wide[0], wide[1] = (0, 1000000) if selection in (1, 3) else (1000000, 0)
    parent[key] = account_wire((hashed, wide, narrow))
    if direct:
        key = chapter_service(255, 42); code, wide, narrow = account_parse(parent[key], 105)
        narrow = list(narrow); narrow[4] = 99
        parent[key] = account_wire((code, wide, narrow)) # Matching creation0 grants source99 authority to credit its junior immediately.
    return parent


def effects(result, direct, selection, slot, *, statistics_config=DEFAULT):
    """Debit only the selected source pool; deferred input alone invokes and stamps the recipient."""
    instructions, _ = program(direct, selection)
    gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+575+(0 if direct else 10000)
    for sid in (42, 99):
        key = chapter_service(255, sid); code, wide, narrow = account_parse(result[key], 105)
        wide, narrow = list(wide), list(narrow)
        if sid == 99:
            wide[int(selection in (1, 3))] -= 7
            narrow[2] = slot
        else:
            wide[int(selection >= 2)] += 7
            if not direct:
                narrow[2] = slot # Immediate account modification alone does not create a C13 participant.
        result[key] = account_wire((code, wide, narrow))
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], statistics_config)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(99, [99]+[0]*11); row[9] += 1; row[11] += gas
    if not direct:
        row = activity.setdefault(42, [42]+[0]*11); row[10] += 1; row[11] += 22
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(direct=direct, selection=selection, sender_gas=gas, delivered=int(not direct))


def expected_observations(check_frozen=True):
    """Calculate thirty-two complete children from eight explicit original pool/authority configurations."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, (direct, selection) in enumerate(PROFILES):
        parent = original(direct, selection); initial = dict(parent); reports = {}
        requests.append('C '+str(index+20)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 6):
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99)] if slot == 3 else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']
            ass = assurances(parent, 5 if slot == 4 else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot == 4 else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                traces[-1].append(dict(slot=slot, **effects(result, direct, selection, slot)))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
    return requests, lines, dict(transitions=32, chains=8, roots=roots, checkpoint_sha256=hashes, traces=traces)
