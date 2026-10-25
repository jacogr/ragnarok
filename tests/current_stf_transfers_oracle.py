# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independently calculated signed whole-block maps for deferred transfer delivery and selection."""
import hashlib
import json
from pathlib import Path
import current_stf_report_guests_oracle as pipeline
from current_stf_effects_oracle import immediate, envelope, gas_definitions, simulate
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, chapter_service, digest
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_accounts_oracle import parse as metadata_parse, wire as metadata_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-transfers.json'
MODES = ('halt', 'panic', 'checkpoint-panic', 'zero-amount', 'low-offer')


def program(mode):
    """Encode only fixed register loads and normative transfer/checkpoint/terminal opcodes."""
    amount = 0 if mode == 'zero-amount' else 7
    offer = 9 if mode == 'low-offer' else 10000
    instructions = [immediate(7, 2**64-1), immediate(8, 42), immediate(9, 0),
                    immediate(10, amount), immediate(11, offer), immediate(12, 196608), bytes([10, 22])]
    if mode == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # The exceptional implication captures the actual outgoing record.
    instructions.append(b'\0' if mode in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, bytes(128), amount, offer


def original(mode):
    """Replace literal service99 code and its reserved request, preserving all other authored namespaces."""
    parent = pipeline.original('create')
    recipient = chapter_service(255, 42)
    code, wide, narrow = metadata_parse(parent[recipient], 105)
    wide = list(wide); wide[3] = 10 # Explicit original transfer minimum, independent of report gas.
    parent[recipient] = metadata_wire((code, wide, narrow))
    key = chapter_service(255, 99)
    code, wide, narrow = metadata_parse(parent[key], 105)
    old = parent.pop(value_key('P', 99, code))
    del parent[request_key(99, code, len(old))]
    instructions, memory, _, _ = program(mode)
    raw = envelope(instructions, memory); hashed = digest(raw)
    parent[value_key('P', 99, hashed)] = raw
    parent[request_key(99, hashed, len(raw))] = request_wire((1,))
    wide = list(wide); wide[4] += len(raw)-len(old)
    parent[key] = metadata_wire((hashed, wide, narrow))
    return parent


def effects(result, mode, slot, *, statistics_config=DEFAULT):
    """Apply paper debit/credit selection, prepaid outgoing gas and recipient-only invocation statistics."""
    instructions, _, amount, offer = program(mode)
    accepted = mode != 'low-offer'
    retained = accepted and mode != 'panic'
    block = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]
    source_gas = block+575+(offer if accepted else 0)+(103 if mode == 'checkpoint-panic' else 0)
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], statistics_config)
    activity = {row[0]: list(row) for row in services}
    source = activity.setdefault(99, [99]+[0]*11)
    source[9] += 1; source[11] += source_gas
    for sid in (42, 99):
        key = chapter_service(255, sid)
        code, wide, narrow = metadata_parse(result[key], 105)
        wide, narrow = list(wide), list(narrow)
        if retained:
            wide[0] += amount if sid == 42 else -amount # Credits occur once in the actual next accumulation round.
        if sid == 99 or retained:
            narrow[2] = slot
        result[key] = metadata_wire((code, wide, narrow))
    if retained:
        row = activity.setdefault(42, [42]+[0]*11)
        row[10] += 1; row[11] += 22 # Literal recipient halt has no work-digest operands.
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return dict(source_gas=source_gas, delivered=int(retained), amount=amount if retained else 0)


def expected_observations(check_frozen=True):
    """Calculate all twenty signed children and complete maps before running the native driver."""
    fixture = json.loads(FIXTURE.read_text()) if check_frozen else {}
    requests, lines, roots, hashes, traces = [], [], [], [], []
    for index, mode in enumerate(MODES):
        initial = original(mode); parent = dict(initial); reports = {}
        requests.append('C '+str(index+5)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 6):
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99)] if slot == 3 else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']
            ass = assurances(parent, 5 if slot == 4 else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot == 4 else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            child, result = pipeline.advance(parent, initial, 'create', slot, gs, ass, plan=plan)
            trace = effects(result, mode, slot) if released else dict(source_gas=0, delivered=0, amount=0)
            parent = result; encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            traces[-1].append(dict(slot=slot, **trace))
    if check_frozen:
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(pipeline.FIXTURE.read_bytes()).hexdigest()
        assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
        assert traces == fixture['traces']
    return requests, lines, dict(transitions=20, chains=5, roots=roots, checkpoint_sha256=hashes, traces=traces)
