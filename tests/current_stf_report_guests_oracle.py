# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Whole-map report-driven guests: independent literal code/gas, admission, release and history.

Original maps derive from the earlier authored guest inputs with all free allowances removed.
Every successor and signed block is calculated before native execution; no observed map is reused.
"""
import hashlib
import json
from pathlib import Path
from current_stf_oracle import (Reader, decode_checkpoint, history, authored_child,
                                advance_no_reports, checkpoint, tree)
from current_stf_effects_oracle import (FIXTURE as BASE, MODES, COMMITMENT, guest, guest_gas,
                                       envelope, gas_definitions, simulate, validate_parent)
from current_stf_reporting_oracle import permutation, assurances, body, pending
from current_stf_verdict_oracle import signed
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as metadata_parse, wire as metadata_wire
from state_history_oracle import wire as history_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT
from state_workqueues_oracle import wire as queue_wire
from state_availability_oracle import wire as availability_wire
from state_service_values_oracle import key as value_key
from report_oracle import encode as report_wire
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-report-guests.json'


def original(mode):
    """Keep the complete frozen authored guest parent, changing only the explicit C12 allowance set."""
    source = json.loads(BASE.read_text())['cases'][MODES.index(mode)]
    parent = decode_checkpoint(bytes.fromhex(source['parent_checkpoint']))
    validate_parent(parent, mode)
    parent[chapter_key(12)] = parent[chapter_key(12)][:-25]+b'\0'
    return parent


def guarantee(parent, initial, core, slot, *, package=None, prerequisites=b'', lookup=b'', service=None, accumulation_gas=100000):
    """Sign a full authored report, explicit dependency families and the actual target service code hash."""
    sid = service if service is not None else ((42 if core == 0 else 99) if slot == 3 else 99)
    fixed = history(initial[chapter_key(3)])[0][0][0]
    pool = Reader(parent[chapter_key(1)])
    pools = [pool.take(32*pool.count()) for _ in range(2)]
    if package is None:
        package = digest(f'immediate package slot{slot} core{core}'.encode()) # Preserve original immediate identities.
    anchor = fixed[:32]+(1).to_bytes(4, 'little')+tree(list(initial.items()))[0]
    header = (package+(100+slot+core).to_bytes(4, 'little')+digest(package+b'segments')
              +(6).to_bytes(2, 'little')+digest(package+b'exports')+(3+core).to_bytes(2, 'little')
              +anchor+bytes(32)+anchor)
    value = dict(header=header, prerequisites=prerequisites, core=core, authorizer=pools[core][:32],
                 gas=17+core, auth=b'auth'+bytes([core]), lookup=lookup,
                 digests=[(sid, metadata_parse(parent[chapter_service(255, sid)], 105)[0],
                           digest(package+b'payload'), accumulation_gas, 0, bytes([slot, core]),
                           (13+core, 2+core, 3+core, 4+core, 5+core))])
    wire = report_wire(value)
    indices = [i for i, at in enumerate(permutation(parent[chapter_key(6)][64:96]))
               if (at//3+(slot % 12)//4) % 2 == core][:2]
    return dict(report=wire, slot=slot, layout=value,
                credentials=[(i, signed(i+1, b'jam_guarantee', digest(wire))[1]) for i in indices])


def inputs(parent, initial, slot):
    """Strict quorum releases one core at a time, then two same-service reports together."""
    gs = [guarantee(parent, initial, core, slot) for core in range(2)] if slot in (3, 6) else []
    count, bits = {4: (4, 3), 5: (5, 2), 6: (5, 1), 7: (5, 3)}.get(slot, (0, 0))
    return gs, assurances(parent, count, bits)


def guest_effect(result, parent, mode, service, count, slot):
    """Apply the literal halt/X or panic/Y implication and account one invocation with all its operands."""
    key = chapter_service(255, service)
    code, wide, narrow = metadata_parse(parent[key], 105)
    wide, narrow = list(wide), list(narrow)
    instructions, memory, value = guest(mode)
    expected_code = envelope([bytes([50, 0])], b'Q') if service == 42 else envelope(instructions, memory)
    assert code == digest(expected_code)
    if service == 99 and mode != 'panic-rollback':
        # Storage replacement removes its old footprint before applying the literal retained write.
        storage = value_key('S', 99, b'\7')
        previous = parent.get(storage)
        if previous is not None:
            narrow[0] -= 1; wide[4] -= 35+len(previous)
        if value:
            narrow[0] += 1; wide[4] += 35+len(value); result[storage] = value
        else: result.pop(storage, None)
    narrow[2] = slot
    result[key] = metadata_wire((code, wide, narrow))
    gas = simulate([bytes([50, 0])], gas_definitions(), prefix=[b'\0']*5)[0] if service == 42 else guest_gas(mode)
    return (service, 0, 0, 0, 0, 0, 0, 0, 0, count, 0, gas)


def accumulated(data):
    """Decode the canonical twelve-row package history independently of ready-report framing."""
    source = Reader(data)
    rows = [source.take(32*source.count()) for _ in range(12)]
    source.done()
    return rows


def advance(parent, initial, mode, slot, gs, ass, *, plan=None):
    """Compose full admission/availability state with immediate or independently planned recursive guest batches."""
    old = pending(parent[chapter_key(10)])
    votes = [sum(bool(item['bits'] & (1 << core)) for item in ass) for core in range(2)]
    released = [old[core]['guarantee']['report'] for core in range(2) if old[core] is not None and votes[core] >= 5]
    # Optional queue mathematics supply processed batches separately from newly available reports.
    processed = released if plan is None else plan['processed']
    if plan is None:
        services = {}
        for wire in processed:
            sid = 42 if wire[:32] == digest(b'immediate package slot3 core0') else 99
            services[sid] = services.get(sid, 0)+1
        batches = [services]
    else:
        assert plan['available'] == released
        batches = plan['batches']
    outputs = ((99, COMMITMENT),) if any(99 in group for group in batches) and mode != 'panic-rollback' else ()
    raw, commitment = body(gs, ass)
    child = authored_child(parent, raw, commitment)
    result = advance_no_reports(parent, child, raw, commitment, outputs=outputs)
    for core in range(2):
        if old[core] is not None and (votes[core] >= 5 or slot >= old[core]['registered']+5): old[core] = None
    pools, rows = Reader(parent[chapter_key(1)]), []
    for core in range(2):
        row = [pools.take(32) for _ in range(pools.count())]
        for item in gs:
            if item['layout']['core'] == core:
                assert old[core] is None and item['layout']['authorizer'] in row
                old[core] = dict(guarantee={k: item[k] for k in ('report', 'slot', 'credentials')}, registered=slot)
                row.remove(item['layout']['authorizer'])
        rows.append(natural(len((row+[bytes(32)])[-8:]))+b''.join((row+[bytes(32)])[-8:]))
    result[chapter_key(1)] = b''.join(rows)
    result[chapter_key(10)] = availability_wire(old)
    blocks, peaks = history(result[chapter_key(3)])
    blocks[-1] = (blocks[-1][0], b''.join(sorted(item['layout']['header'][:32]+item['layout']['header'][70:102] for item in gs)))
    result[chapter_key(3)] = history_wire((blocks, peaks))
    if plan is None:
        assert parent[chapter_key(14)] == bytes(12) # Original immediate reports fit the block budget.
        result[chapter_key(14)] = bytes(12)
    else: result[chapter_key(14)] = queue_wire('R', plan['ready'])
    result[chapter_key(15)] = queue_wire('A', accumulated(parent[chapter_key(15)])[1:]+[b''.join(sorted(wire[:32] for wire in processed))])
    (current, previous, _, _), _ = statistics_parse(result[chapter_key(13)], DEFAULT)
    for index in {i for item in gs for i, _ in item['credentials']}:
        row = list(current[index]); row[4] += 1; current[index] = tuple(row)
    for item in ass:
        row = list(current[item['index']]); row[5] += 1; current[item['index']] = tuple(row)
    cores, activity = [[0]*8 for _ in range(2)], {}
    for item in gs:
        value = item['layout']; sid = value['digests'][0][0]
        load = value['digests'][0][-1]
        cores[value['core']][2:] = [*load[1:], int.from_bytes(value['header'][32:36], 'little'), load[0]]
        row = activity.setdefault(sid, [sid]+[0]*11)
        row[3] += 1
        for index, amount in enumerate(load, 4): row[index] += amount
    for core in range(2): cores[core][1] = votes[core]
    for wire in released:
        core = wire[273] if plan is None else plan['reports'][wire[:32]]['core'] # Deferred reports have variable dependency framing.
        cores[core][0] = int.from_bytes(wire[32:36], 'little')+4104*((65*int.from_bytes(wire[102:104], 'little')+63)//64)
    for group in batches:
        prior = dict(result) # Each recursive guest sees the actual earlier mathematical batch's state.
        for sid, count in sorted(group.items()):
            row = guest_effect(result, prior, mode, sid, count, slot)
            combined = activity.setdefault(sid, [sid]+[0]*11)
            for index in range(1, 12): combined[index] += row[index]
    result[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[sid]) for sid in sorted(activity)]))
    return child, result


def expected_observations(check_frozen=True):
    """Freeze every expected whole map before the native program receives the first input."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['base_fixture_sha256'] == hashlib.sha256(BASE.read_bytes()).hexdigest()
    requests, lines, roots, hashes = [], [], [], []
    for mode in MODES:
        initial = original(mode); parent = dict(initial); roots.append([]); hashes.append([])
        requests.append('C '+str(MODES.index(mode))); lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in range(2, 9):
            gs, ass = inputs(parent, initial, slot)
            child, parent = advance(parent, initial, mode, slot, gs, ass)
            encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
    return requests, lines, dict(transitions=35, chains=5, guest_executions=15, processed_reports=20,
                                roots=roots, checkpoint_sha256=hashes)
