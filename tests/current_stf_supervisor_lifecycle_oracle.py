# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole maps for self-supervisor reassignment, current authority and protected-pool funding."""
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

FIXTURE = Path(__file__).parent/'fixtures/current-stf-supervisor-lifecycle.json'
PROFILES = ('assign-other', 'assign-self', 'missing-nominee', 'panic', 'checkpoint-panic')


def program(profile):
    """Literal supervisor29 precedes a protected-source transfer22; every selector is set explicitly."""
    nominee = 2**64-1 if profile == 'assign-self' else (77 if profile == 'missing-nominee' else 42)
    instructions = [immediate(7, 2**64-1), immediate(8, nominee), bytes([10, 29])]
    if profile == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # Capture only the supervisor change before the later transfer attempt.
    instructions += [immediate(7, 2**64-1), immediate(8, 42), immediate(9, 1), immediate(10, 7),
                     immediate(11, 10000), immediate(12, 196608), bytes([10, 22])]
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, bytes(128)


def original(profile):
    """Fund only the protected source pool and reserve honest code bytes in the original namespace."""
    parent = transfers.original('halt'); key = chapter_service(255, 99)
    old_hash, wide, narrow = account_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, old_hash)); del parent[request_key(99, old_hash, len(old))]
    instructions, memory = program(profile); raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw
    parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old); wide[0] = 0; wide[1] = 1000000
    parent[key] = account_wire((hashed, wide, narrow))
    return parent


def effects(result, parent, profile, slot, budget, *, statistics_config=DEFAULT):
    """Each host sees the current regular metadata; terminal selection can restore the original or checkpoint supervisor."""
    key = chapter_service(255, 99); code, wide, narrow = account_parse(parent[key], 105)
    wide, narrow = list(wide), list(narrow)
    prior_supervisor = narrow[4] if narrow[4] in (42, 99) and narrow[5] == 0 else 99
    nominee = 99 if profile == 'assign-self' else (77 if profile == 'missing-nominee' else 42)
    assigned = prior_supervisor == 99 and nominee in (42, 99)
    current_supervisor = nominee if assigned else prior_supervisor
    transfer_allowed = current_supervisor == 99 and wide[1] >= 7
    retained = profile != 'panic'
    delivered = transfer_allowed and retained # The checkpoint variant selects a pre-transfer prefix, but already lost protected-funding authority.
    instructions, _ = program(profile)
    gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+1000+575+(10000 if transfer_allowed else 0)+(103 if profile == 'checkpoint-panic' else 0)
    assert gas <= budget
    if assigned and retained:
        narrow[4] = nominee; narrow[5] = 0 # Both explicitly present nominees have creation0 in this original map.
    if delivered:
        wide[1] -= 7
        target = chapter_service(255, 42); tcode, twide, tnarrow = account_parse(result[target], 105)
        twide, tnarrow = list(twide), list(tnarrow); twide[0] += 7; tnarrow[2] = slot
        result[target] = account_wire((tcode, twide, tnarrow))
    narrow[2] = slot
    result[key] = account_wire((code, wide, narrow))
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], statistics_config)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(99, [99]+[0]*11); row[9] += 1; row[11] += gas
    if delivered:
        row = activity.setdefault(42, [42]+[0]*11); row[10] += 1; row[11] += 22
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(slot=slot, gas=gas, assigned=assigned and retained, delivered=delivered,
                stored_supervisor=narrow[4], protected_balance=wide[1])


def expected_observations(check_frozen=True):
    """Calculate thirty full transitions including two independently signed report releases per original."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}; budgets = {}
        requests.append('C '+str(index+52)); lines.append('P '+checkpoint(list(parent.items())).hex())
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
