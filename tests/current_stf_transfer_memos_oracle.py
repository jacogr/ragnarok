# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent memo encoding/fetch, storage footprint and yielded-output whole-map effects."""
import hashlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers
from current_stf_effects_oracle import immediate, envelope, simulate, gas_definitions
from current_stf_reporting_oracle import body, assurances
from current_stf_oracle import checkpoint, tree, authored_child, advance_no_reports
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key, wire as request_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT

FIXTURE = Path(__file__).parent/'fixtures/current-stf-transfer-memos.json'
PROFILES = ('whole-list', 'single-item', 'panic', 'checkpoint-panic', 'clamped-tail')


def sender():
    """The source's literal128 distinct memory bytes become one real deferred memo."""
    instructions, _, _, _ = transfers.program('halt')
    return instructions, bytes(range(128))


def program(profile):
    """Independently encode fetch14/15, write32, yield32 and optional checkpoint with initialized tail sentinels."""
    offset = 131 if profile == 'clamped-tail' else (18 if profile == 'single-item' else 19)
    selector = 15 if profile == 'single-item' else 14
    instructions = [immediate(7, 196608), immediate(8, offset), immediate(9, 32), immediate(10, selector),
                    immediate(11, 0), bytes([10, 2]), immediate(7, 2**64-1), immediate(8, 196640),
                    immediate(9, 1), immediate(10, 196608), immediate(11, 32), bytes([10, 5]),
                    immediate(7, 196608), bytes([10, 27])]
    if profile == 'checkpoint-panic':
        instructions.append(bytes([10, 19])) # Only a real checkpoint retains fetched effects after the final panic.
    instructions.append(b'\0' if profile in ('panic', 'checkpoint-panic') else bytes([50, 0]))
    return instructions, bytes([170])*32+b'\7'+bytes(31)


def fetched(profile):
    """Canonical transfer tag1, source/destination E4, Boolean, amount E8, fixed memo128 and gas E8 are literal bytes."""
    item = b'\1'+(99).to_bytes(4, 'little')+(42).to_bytes(4, 'little')+b'\0'+(7).to_bytes(8, 'little')+bytes(range(128))+(10000).to_bytes(8, 'little')
    source = item if profile == 'single-item' else b'\1'+item
    offset = 131 if profile == 'clamped-tail' else (18 if profile == 'single-item' else 19)
    copied = source[offset:offset+32]
    buffer = bytearray([170]*32); buffer[:len(copied)] = copied
    return bytes(buffer)


def original(profile):
    """Reserve honest literal code identities for both services while preserving all unrelated namespaces."""
    parent = transfers.original('halt')
    for sid, (instructions, memory) in ((42, program(profile)), (99, sender())):
        key = chapter_service(255, sid); old_hash, wide, narrow = account_parse(parent[key], 105)
        old = parent.pop(value_key('P', sid, old_hash)); del parent[request_key(sid, old_hash, len(old))]
        raw = envelope(instructions, memory); hashed = digest(raw)
        parent[value_key('P', sid, hashed)] = raw
        parent[request_key(sid, hashed, len(raw))] = request_wire((1,))
        wide = list(wide); wide[4] += len(raw)-len(old)
        parent[key] = account_wire((hashed, wide, narrow))
    assert value_key('S', 42, b'\7') not in parent
    return parent


def foundation(parent, outputs):
    """Bind output/history equations to the independent literal fetched bytes before any actual guest executes."""
    def advance(raw, commitment, ignored_outputs):
        """The existing block/history reference receives only the explicitly selected independent output pairs."""
        child = authored_child(parent, raw, commitment)
        return child, advance_no_reports(parent, child, raw, commitment, outputs=outputs)
    return advance


def effects(result, profile, slot, *, statistics_config=DEFAULT):
    """Compute transfer credit, selected storage footprint and N/T/G from literal instructions and host prices."""
    transfers.effects(result, 'halt', slot, statistics_config=statistics_config)
    instructions, _ = program(profile); retained = profile != 'panic'
    fetch = 366 if profile == 'single-item' else 300 # GP fetch15=355+ceil(344*32/1024); fetch14=287+ceil(400*32/1024).
    gas = simulate(instructions, gas_definitions(), prefix=[b'\0']*5)[0]+fetch+2453+98+(103 if profile == 'checkpoint-panic' else 0)
    if retained:
        value = fetched(profile); storage = value_key('S', 42, b'\7'); fresh = storage not in result
        result[storage] = value
        key = chapter_service(255, 42); code, wide, narrow = account_parse(result[key], 105)
        wide, narrow = list(wide), list(narrow); wide[4] += 67*int(fresh); narrow[0] += int(fresh)
        result[key] = account_wire((code, wide, narrow))
    (current, previous, cores, services), _ = statistics_parse(result[chapter_key(13)], statistics_config)
    services = [tuple(list(row[:11])+[gas]) if row[0] == 42 else row for row in services]
    result[chapter_key(13)] = statistics_wire((current, previous, cores, services))
    return dict(receiver_gas=gas, retained=retained, fetched=fetched(profile).hex())


def expected_observations(check_frozen=True):
    """Calculate twenty signed children whose memo bytes determine both storage and C16 outputs."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    pipeline = transfers.pipeline
    for index, profile in enumerate(PROFILES):
        parent = original(profile); initial = dict(parent); reports = {}
        requests.append('C '+str(index+42)); lines.append('P '+checkpoint(list(parent.items())).hex())
        roots.append([]); hashes.append([]); traces.append([])
        for slot in range(2, 6):
            gs = [pipeline.guarantee(parent, initial, 1, slot, service=99)] if slot == 3 else []
            for item in gs:
                reports[item['report'][:32]] = item['layout']
            ass = assurances(parent, 5 if slot == 4 else 0, 2)
            released = [item['guarantee']['report'] for item in pipeline.pending(parent[chapter_key(10)]) if item is not None] if slot == 4 else []
            plan = dict(available=released, processed=released, batches=[], ready=[[] for _ in range(12)], reports=reports, yielded=False)
            plan['foundation'] = foundation(parent, ((42, fetched(profile)),) if released and profile != 'panic' else ())
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
