# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map queued provision, request relevance and checkpoint-prefix lifecycle cases."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-preimage-provision.json'
PROFILES = ('provide', 'panic', 'checkpoint-panic', 'forget-provide', 'provide-forget')
PAYLOAD = b'R'


def program(profile):
    """Queue R only while pending, selecting ordinary or checkpointed effects before later relevance filtering."""
    operations = {'provide': (28,), 'panic': (28,), 'checkpoint-panic': (28, 19),
                  'forget-provide': (26, 28), 'provide-forget': (28, 26)}[profile]
    instructions = []
    for operation in operations:
        if operation == 19:
            instructions.append(bytes([10, 19])) # Select the queued provision before panic.
        else:
            pointer = 196608 if operation == 26 else 196640
            instructions += [immediate(7, 2**64-1), immediate(8, pointer), immediate(9, 1), bytes([10, operation])]
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, digest(PAYLOAD)+PAYLOAD, operations


def original(profile):
    """Every original has a genuine pending R request and no R preimage, distinct from code availability."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory, _ = program(profile); raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw
    parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    parent[request_key(99, digest(PAYLOAD), 1)] = request_wire(())
    wide, narrow = list(wide), list(narrow); wide[4] += len(raw)-len(old)+82; narrow[0] += 2
    parent[key] = account_wire((hashed, wide, narrow))
    return parent


def effects(result, parent, profile, slot, budget):
    """Fulfill still-relevant selected provisions after account changes; VM provision does not count as an extrinsic preimage."""
    request = request_key(99, digest(PAYLOAD), 1); preimage = value_key('P', 99, digest(PAYLOAD))
    deleted = profile in ('forget-provide', 'provide-forget'); present = request in parent
    fulfilled = profile in ('provide', 'checkpoint-panic')
    if deleted:
        result.pop(request, None); result.pop(preimage, None) # A queued value with a forgotten request is irrelevant.
    elif fulfilled and preimage not in parent:
        result[request] = request_wire((slot,)); result[preimage] = PAYLOAD
    code, wide, narrow = account_parse(parent[chapter_service(255, 99)], 105)
    wide, narrow = list(wide), list(narrow)
    delta = -int(deleted and present); wide[4] += 82*delta; narrow[0] += 2*delta; narrow[2] = slot
    result[chapter_service(255, 99)] = account_wire((code, wide, narrow))
    instructions, _, operations = program(profile)
    gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+sum({28: 3983, 26: 3250, 19: 103}[operation] for operation in operations)
    assert gas <= budget
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], DEFAULT)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(99, [99]+[0]*11); row[9] += 1; row[11] += gas
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot, gas=gas, request_after=request in result, preimage_after=preimage in result, footprint_delta=82*delta)


def expected_observations(check_frozen=True):
    """Calculate thirty full transitions with two report releases and selected provision/request namespace versions."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+67)); lines.append('P '+checkpoint(list(parent.items())).hex())
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
