# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map transfer refusals, exact host budgets and prepaid recipient block boundaries."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-transfer-admission.json'
PROFILES = ('unknown-source', 'unknown-destination', 'unauthorized-source', 'insufficient-balance',
            'invalid-pool', 'invalid-memo-range', 'below-minimum', 'minimum-zero-execution',
            'exact-outgoing-budget', 'outgoing-one-above', 'recipient-one-short', 'recipient-exact',
            'full-width-source', 'full-width-destination')


def parameters(profile):
    """Trusted literal register values independently specify each non-overlapping boundary witness."""
    fields = dict(source=2**64-1, destination=42, selection=0, amount=7, offer=10000, memo=196608)
    changes = {
        'unknown-source': dict(source=77), 'unknown-destination': dict(destination=77),
        'unauthorized-source': dict(source=42), 'insufficient-balance': dict(amount=1000001),
        'invalid-pool': dict(selection=4), 'invalid-memo-range': dict(memo=2**64-64),
        'below-minimum': dict(offer=9), 'minimum-zero-execution': dict(offer=10),
        'exact-outgoing-budget': dict(offer=99322), 'outgoing-one-above': dict(offer=99323),
        'recipient-one-short': dict(offer=21), 'recipient-exact': dict(offer=22),
        'full-width-source': dict(source=2**32+99), 'full-width-destination': dict(destination=2**32+42)}
    fields.update(changes[profile])
    return fields


def program(profile):
    """Encode the literal six register loads, one transfer call and halt independently of native helpers."""
    fields = parameters(profile)
    instructions = [immediate(register, fields[field]) for register, field in
                    zip(range(7, 13), ('source', 'destination', 'selection', 'amount', 'offer', 'memo'))]
    return instructions+[bytes([10, 22]), bytes([50, 0])], bytes(128)


def original(profile):
    """Reserve the exact authored code/request footprint without changing funding or recipient minimum."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory = program(profile)
    raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw
    parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old)
    parent[key] = account_wire((hashed, wide, narrow))
    return parent


def effects(result, profile, slot, *, statistics_config=DEFAULT):
    """Account preflight-only refusal, host exhaustion or accepted debit/input without reading a native verdict."""
    fields = parameters(profile); instructions, _ = program(profile)
    block = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]
    assert block+575 == 678
    valid = (fields['source'] == 2**64-1 and fields['destination'] == 42 and fields['selection'] == 0
             and fields['amount'] <= 1000000 and fields['offer'] >= 10 and fields['memo'] == 196608)
    affordable = block+575+fields['offer'] <= 100000
    retained = valid and affordable
    gas = (block+575+fields['offer'] if affordable else 100000) if valid else block+575
    recipient_gas = 22 if retained and fields['offer'] >= 22 else 0
    for sid in (42, 99):
        key = chapter_service(255, sid); code, wide, narrow = account_parse(result[key], 105)
        wide, narrow = list(wide), list(narrow)
        if retained:
            wide[0] += fields['amount'] if sid == 42 else -fields['amount']
        if sid == 99 or retained:
            narrow[2] = slot # A processed transfer stamps the recipient even when its whole block is unaffordable.
        result[key] = account_wire((code, wide, narrow))
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], statistics_config)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(99, [99]+[0]*11); row[9] += 1; row[11] += gas
    if retained:
        row = activity.setdefault(42, [42]+[0]*11); row[10] += 1; row[11] += recipient_gas
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(profile=profile, retained=retained, sender_gas=gas, recipient_gas=recipient_gas)


def expected_observations(check_frozen=True):
    """Calculate fifty-six complete children for fourteen explicit admission and gas boundaries."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}
        requests.append('C '+str(index+28)); lines.append('P '+checkpoint(list(parent.items())).hex())
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
                traces[-1].append(dict(slot=slot, **effects(result, profile, slot)))
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
    return requests, lines, dict(transitions=56, chains=14, roots=roots, checkpoint_sha256=hashes, traces=traces)
