# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole maps for current new20, compact entropy-derived cursors and published child namespaces."""
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
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-service-creation.json'
PROFILES = ('halt', 'panic', 'checkpoint-panic', 'two-children', 'reserved-length')


def replacement():
    """New services request honest literal halt code, but creation does not supply its preimage."""
    return envelope([bytes([50, 0])], b'Q')


def program(profile):
    """Literal current60-byte descriptor contains hash32/lengthE4/minimumGasE8/E8/gratisE8."""
    length = 2**32-2 if profile == 'reserved-length' else len(replacement())
    memory = digest(replacement())+length.to_bytes(4, 'little')+(100).to_bytes(8, 'little')+(19).to_bytes(8, 'little')+bytes(8)
    instructions = []
    for _ in range(2 if profile == 'two-children' else 1):
        instructions += [immediate(7, 2**64-1), immediate(8, 2**64-1), immediate(9, 0), immediate(10, 196608), bytes([10, 20])]
    if profile == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # Preserve the actual first child's request and next cursor together.
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, memory


def original(profile):
    """Only the creator's literal code/request reservation changes from the earlier complete funded map."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory = program(profile); raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw
    parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old)
    parent[key] = account_wire((hashed, wide, narrow))
    return parent


def creation_ids(result, slot, count):
    """GP seed uses compact creator/slot integers and raw posterior eta0; public cursors advance by42."""
    space = 2**32-65536-256
    raw = int.from_bytes(digest(natural(99)+result[chapter_key(6)][:32]+natural(slot))[:4], 'little')
    cursor = 65536+raw % space
    ids = []
    for _ in range(count):
        assert 65536 <= cursor < 2**32-256 and chapter_service(255, cursor) not in result
        ids.append(cursor)
        cursor = 65536+(cursor-65536+42) % space
    assert len(set(ids)) == count
    return ids


def effects(result, profile, slot, *, statistics_config=DEFAULT):
    """Zero deposit parameters give zero child debit; literal metadata and empty code requests still publish atomically."""
    instructions, _ = program(profile); calls = 2 if profile == 'two-children' else 1
    count = 0 if profile in ('panic', 'reserved-length') else calls
    ids = creation_ids(result, slot, count)
    target = replacement(); hashed = digest(target)
    for service in ids:
        metadata = (hashed, (0, 0, 100, 19, 81+len(target), 0), (2, slot, 0, 99, 99, 0))
        result[chapter_service(255, service)] = account_wire(metadata)
        result[request_key(service, hashed, len(target))] = request_wire(())
        assert value_key('P', service, hashed) not in result
    key = chapter_service(255, 99); code, wide, narrow = account_parse(result[key], 105)
    narrow = list(narrow); narrow[2] = slot
    result[key] = account_wire((code, wide, narrow))
    gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+3855*calls+(103 if profile == 'checkpoint-panic' else 0)
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], statistics_config)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(99, [99]+[0]*11); row[9] += 1; row[11] += gas
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(created=ids, gas=gas, calls=calls)


def expected_observations(check_frozen=True):
    """Calculate twenty complete children with independently derived new account IDs and code-request namespaces."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}
        requests.append('C '+str(index+57)); lines.append('P '+checkpoint(list(parent.items())).hex())
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
    return requests, lines, dict(transitions=20, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
