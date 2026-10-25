# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map supervised foreign upgrades and subsequent junior current-code lookup."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-supervised-upgrades.json'
PROFILES = ('upgrade', 'panic', 'checkpoint-panic', 'missing-target-code', 'stale-supervisor')


def replacement():
    """The U-memory halt has a different complete-code identity from42's original Q-memory halt."""
    return envelope([bytes([50, 0])], b'U')


def program(profile):
    """Foreign upgrade21 changes only42 code/minima under the actual original supervisor incarnation."""
    instructions = [immediate(7, 42), immediate(8, 196608), immediate(9, 100),
                    immediate(10, 19), bytes([10, 21])]
    if profile == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # Capture foreign metadata before exceptional selection.
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, digest(replacement())


def original(profile):
    """Reserve replacement code in42 before any signed child, with honest missing-code availability."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory = program(profile); raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw; parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old); parent[key] = account_wire((hashed, wide, narrow))
    target = replacement(); hashed = digest(target)
    parent[request_key(42, hashed, len(target))] = request_wire(()) if profile == 'missing-target-code' else request_wire((1,))
    if profile != 'missing-target-code':
        parent[value_key('P', 42, hashed)] = target # Upgrade never invents code availability.
    key = chapter_service(255, 42); code, wide, narrow = account_parse(parent[key], 105)
    wide, narrow = list(wide), list(narrow); wide[4] += 81+len(target); narrow[0] += 2
    narrow[4] = 99; narrow[5] = int(profile == 'stale-supervisor')
    parent[key] = account_wire((code, wide, narrow))
    return parent


def effects(result, parent, profile, slot, budget, *, recipient_slots=(6,), statistics_config=DEFAULT):
    """Only99 can change the selected foreign metadata; later42 invocation resolves its actual prior code namespace."""
    service = 42 if slot in recipient_slots else 99
    if service == 42:
        code, _, _ = account_parse(parent[chapter_service(255, 42)], 105)
        gas = 22 if value_key('P', 42, code) in parent else 0 # Missing current code is processed with N1/G0.
    else:
        instructions, _ = program(profile)
        gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+1028+103*int(profile == 'checkpoint-panic')
        if profile not in ('panic', 'stale-supervisor'):
            key = chapter_service(255, 42); _, wide, narrow = account_parse(parent[key], 105)
            wide = list(wide); wide[2] = 100; wide[3] = 19
            result[key] = account_wire((digest(replacement()), wide, narrow))
    assert gas <= budget
    key = chapter_service(255, service); code, wide, narrow = account_parse(result[key], 105)
    narrow = list(narrow); narrow[2] = slot; result[key] = account_wire((code, wide, narrow))
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], statistics_config)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(service, [service]+[0]*11); row[9] += 1; row[11] += gas
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot, service=service, gas=gas, target_hash=account_parse(result[chapter_service(255, 42)], 105)[0].hex())


def expected_observations(check_frozen=True):
    """Calculate forty full transitions including three independently signed report releases per original."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+92)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 10):
            budget = 100000
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=(42 if slot == 5 else 99), accumulation_gas=budget)] if slot in (3, 5, 7) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot in (4, 6, 8) else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4, 6, 8) else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            if released:
                assert len(released) == 1
                traces[-1].append(effects(result, parent, profile, slot, budgets[released[0][:32]]))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
    return requests, lines, dict(transitions=40, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
