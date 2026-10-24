# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole maps for prepaid-block and host OOG, pooled limits and checkpoint selection."""
import hashlib
import json
from pathlib import Path
import current_stf_report_guests_oracle as pipeline
from current_stf_reporting_oracle import pending, assurances, body
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, digest

FIXTURE = Path(__file__).parent/'fixtures/current-stf-gas-exits.json'
BUDGETS = (1, 105, 1325, 1377, 2753)
CASES = [(mode, budget) for mode in pipeline.MODES for budget in BUDGETS]


def outcome(mode, budget):
    """Charge the pinned whole block first, then literal GP hosts; OOG selects uncheckpointed Y."""
    instructions, _, value = pipeline.guest(mode)
    block = pipeline.simulate(instructions, pipeline.gas_definitions(), prefix=[b'\0']*5)[0]
    if budget < block: return dict(charge=0, retained=False, exit='basic-block')
    remaining = budget-block
    hosts = [('write', 2442+(3358+1023)//1024+(216*len(value)+1023)//1024), ('yield', 98)]
    if mode == 'checkpoint-panic': hosts.append(('checkpoint', 103))
    for name, cost in hosts:
        if remaining < cost: return dict(charge=budget, retained=False, exit=name)
        remaining -= cost
    return dict(charge=budget-remaining, retained=mode != 'panic-rollback', exit='terminal')


def inputs(parent, initial, slot, budget, reports):
    """Identical report and assurance ordering isolates one operand versus two pooled operands."""
    gs = []
    if slot in (3, 6):
        for core in range(2):
            sid = 42 if slot == 3 and core == 0 else 99
            item = pipeline.guarantee(parent, initial, core, slot, service=sid,
                       package=digest(f'gas-exit report {slot} {core}'.encode()),
                       accumulation_gas=22 if sid == 42 else budget)
            reports[item['report'][:32]] = item['layout']; gs.append(item)
    count, bits = {4: (4, 3), 5: (5, 2), 6: (5, 1), 7: (5, 3)}.get(slot, (0, 0))
    return gs, assurances(parent, count, bits)


def plan(parent, mode, ass, reports):
    """Every immediate available report fits; pooled service limits determine literal guest implications."""
    old = pending(parent[chapter_key(10)])
    available = [old[core]['guarantee']['report'] for core in range(2) if old[core] is not None
                 and sum(bool(item['bits'] & (1 << core)) for item in ass) >= 5]
    group, budgets = {}, {}
    for wire in available:
        for item in reports[wire[:32]]['digests']:
            sid = item[0]; group[sid] = group.get(sid, 0)+1; budgets[sid] = budgets.get(sid, 0)+item[3]
    effects, trace = {}, {}
    for sid, budget in budgets.items():
        calculated = dict(charge=22, retained=False, exit='halt') if sid == 42 else outcome(mode, budget)
        trace[sid] = calculated
        effects[sid] = {key: calculated[key] for key in ('charge', 'retained')}
    return dict(available=available, processed=available, batches=[group] if group else [],
                ready=[[] for _ in range(12)], reports=reports, effects=[effects] if group else [],
                yielded=99 in effects and effects[99]['retained'], trace=trace)


def expected_observations(check_frozen=True):
    """Freeze175 full-map transitions before the shared native driver reads its first body."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['base_fixture_sha256'] == hashlib.sha256(pipeline.FIXTURE.read_bytes()).hexdigest()
    requests, lines, roots, hashes = [], [], [], []
    for mode, budget in CASES:
        initial = pipeline.original(mode); parent = dict(initial); reports = {}
        roots.append([]); hashes.append([])
        requests.append('C '+str(pipeline.MODES.index(mode))); lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in range(2, 9):
            gs, ass = inputs(parent, initial, slot, budget, reports)
            projection = plan(parent, mode, ass, reports)
            child, parent = pipeline.advance(parent, initial, mode, slot, gs, ass, plan=projection)
            encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen: assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
    return requests, lines, dict(transitions=175, chains=25, processed_reports=100,
                                roots=roots, checkpoint_sha256=hashes)
