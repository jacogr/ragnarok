# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map privileged manager handoff, authorization and checkpoint lifecycle cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-manager-handoff.json'
PROFILES = ('handoff', 'panic', 'checkpoint-panic', 'self', 'unauthorized')
PAYLOAD = b'R'


from state_privileges_oracle import wire as privileges_wire


def program(profile):
    """Bless resets all fixed roles with no allowances, under a single unambiguous manager authority."""
    instructions = [immediate(7, 99 if profile == 'self' else 42), immediate(8, 196608),
                    immediate(9, 0), immediate(10, 0), immediate(11, 196616), immediate(12, 0), bytes([10, 16])]
    if profile == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # Exceptional role selection retains the precise manager handoff.
    instructions += [immediate(7, 99), bytes([10, 16])] # A caller that handed off authority cannot restore itself.
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, bytes(8)


def original(profile):
    """One current manager is assigned before signing; no allowance or second privileged actor can conflict."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory = program(profile); raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw; parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old)
    parent[key] = account_wire((hashed, wide, narrow))
    parent[chapter_key(12)] = privileges_wire((42 if profile == 'unauthorized' else 99, 0, 0, [0, 0], []))
    return parent


def effects(result, parent, profile, slot, budget):
    """Retained roles come from the sole authorized manager; a handed-off caller subsequently receives HUH."""
    if profile in ('handoff', 'checkpoint-panic'):
        result[chapter_key(12)] = privileges_wire((42, 0, 0, [0, 0], []))
    code, wide, narrow = account_parse(parent[chapter_service(255, 99)], 105)
    narrow = list(narrow); narrow[2] = slot
    result[chapter_service(255, 99)] = account_wire((code, wide, narrow))
    instructions, _ = program(profile)
    gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+844+103*int(profile == 'checkpoint-panic')
    assert gas <= budget
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], DEFAULT)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(99, [99]+[0]*11); row[9] += 1; row[11] += gas
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot, gas=gas, manager=int.from_bytes(result[chapter_key(12)][:4], 'little'))


def expected_observations(check_frozen=True):
    """Calculate thirty full transitions with two report releases and selected privileged role handoff maps."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+77)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 8):
            budget = 100000
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99, accumulation_gas=budget)] if slot in (3, 5) else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']; budgets[item['report'][:32]] = budget
            ass = assurances(parent, 5 if slot in (4, 6) else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot in (4, 6) else []
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
    return requests, lines, dict(transitions=30, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
