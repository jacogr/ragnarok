# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete maps for repeated deferred transfer invocation, exceptional selection and zero-gas credit."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-forwarded-transfers.json'
PROFILES = ('halt', 'panic', 'checkpoint-panic', 'zero-offer', 'zero-amount')


def program(profile):
    """Literal receiver code forwards three tokens with1000 gas, except the explicit zero-field variants."""
    amount = 0 if profile == 'zero-amount' else 3
    offer = 0 if profile == 'zero-offer' else 1000
    instructions = [immediate(7, 2**64-1), immediate(8, 99), immediate(9, 0), immediate(10, amount),
                    immediate(11, offer), immediate(12, 196608), bytes([10, 22])]
    if profile == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # Exceptional selection captures the actual completed transfer.
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, bytes(128), amount, offer


def original(profile):
    """Replace only the recipient's literal code/request and corresponding reserved byte footprint."""
    parent = transfers.original('halt'); key = chapter_service(255, 42)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 42, old_hash)); del parent[request_key(42, old_hash, len(old))]
    instructions, memory, _, _ = program(profile)
    raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 42, hashed)] = raw
    parent[request_key(42, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old)
    parent[key] = account_wire((hashed, wide, narrow))
    return parent


def effects(result, profile, slot):
    """Select both transfers independently; third-round host OOG retains incoming credit but emits no further transfer."""
    transfers.effects(result, 'halt', slot)
    instructions, _, amount, offer = program(profile)
    retained = profile != 'panic'
    gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+575+offer+(103 if profile == 'checkpoint-panic' else 0)
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], DEFAULT)
    activity = {row[0]: list(row) for row in services}
    activity[42][11] = gas
    if retained:
        # Incoming1000 pays the whole basic block but cannot pay the sender's10575 host call; zero offer cannot even enter the block.
        activity[99][10] += 1; activity[99][11] += offer
        for sid, delta in ((42, -amount), (99, amount)):
            key = chapter_service(255, sid)
            code, wide, narrow = account_parse(result[key], 105)
            wide = list(wide); wide[0] += delta
            result[key] = account_wire((code, wide, narrow))
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(forwarded=int(retained), returned_amount=amount if retained else 0,
                receiver_gas=gas, sender_reentry_gas=offer if retained else 0)


def expected_observations(check_frozen=True):
    """Calculate twenty complete signed children without native state, gas or successor observations."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}
        requests.append('C '+str(index+15)); lines.append('P '+checkpoint(list(parent.items())).hex())
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
