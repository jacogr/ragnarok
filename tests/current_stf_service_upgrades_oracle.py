# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map code upgrades, minimum gas changes and later current-code invocation behavior."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-service-upgrades.json'
PROFILES = ('halt', 'panic', 'checkpoint-panic', 'missing-target-code', 'host-oog')


def replacement():
    """Exact literal halt code has a separate service99 request/preimage identity from service42's identical code."""
    return envelope([bytes([50, 0])], b'Q')


def program(profile):
    """Literal upgrade21 writes its own code hash, minimum accumulation100 and transfer19."""
    instructions = [immediate(7, 2**64-1), immediate(8, 196608), immediate(9, 100),
                    immediate(10, 19), bytes([10, 21])]
    if profile == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # Only an actual checkpoint captures this regular mutation.
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, digest(replacement())


def original(profile):
    """Reserve actual original and replacement code requests with honest available/missing histories and footprints."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory = program(profile); raw = envelope(instructions, memory); hashed = digest(raw)
    target = replacement(); target_hash = digest(target)
    parent[value_key('P', 99, hashed)] = raw
    parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    parent[request_key(99, target_hash, len(target))] = request_wire(()) if profile == 'missing-target-code' else request_wire((1,))
    if profile != 'missing-target-code':
        parent[value_key('P', 99, target_hash)] = target
    wide, narrow = list(wide), list(narrow)
    wide[4] += len(raw)-len(old)+81+len(target); narrow[0] += 2
    parent[key] = account_wire((hashed, wide, narrow))
    return parent


def effects(result, parent, profile, slot, budget):
    """Choose code from the actual prior mathematical account; mutations affect only later invocations."""
    key = chapter_service(255, 99); code, wide, narrow = account_parse(parent[key], 105)
    wide, narrow = list(wide), list(narrow)
    target_hash = digest(replacement()); upgraded = False
    if code == target_hash:
        # Missing code is a zero-gas processed work item; present literal halt pays exactly22.
        gas = 22 if value_key('P', 99, target_hash) in parent else 0
    else:
        instructions, memory = program(profile)
        assert code == digest(envelope(instructions, memory))
        full = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+1028+(103 if profile == 'checkpoint-panic' else 0)
        gas = min(budget, full)
        upgraded = budget >= full and profile != 'panic'
        if upgraded:
            code = target_hash; wide[2] = 100; wide[3] = 19
    narrow[2] = slot # N=1 retains the statistics key, even for absent replacement code with G=0.
    result[key] = account_wire((code, wide, narrow))
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], DEFAULT)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(99, [99]+[0]*11); row[9] += 1; row[11] += gas
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot, gas=gas, applied_upgrade=upgraded, code_hash=code.hex(), minimum_gas=wide[2:4])


def expected_observations(check_frozen=True):
    """Calculate forty full transitions including three independently signed report releases per original."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+47)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 10):
            budget = 500 if profile == 'host-oog' and slot == 3 else 100000
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99, accumulation_gas=budget)] if slot in (3, 5, 7) else []
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
