# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map deferred dependency waves and declared/actual-gas continuation.

All waiting reports enter through genuine guarantees and availability. The mathematical E/Q and
accseq calculations below use no native queue, gas observation or successor state.
"""
import hashlib
import json
from pathlib import Path
import current_stf_report_guests_oracle as pipeline
from current_stf_reporting_oracle import ready, pending, assurances, body
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, digest

FIXTURE = Path(__file__).parent/'fixtures/current-stf-dependency-waves.json'
CASES = [(mode, False) for mode in pipeline.MODES]+[('create', True), ('checkpoint-panic', True)]


def package(name):
    """Distinct authored package identities have no relationship to service IDs or queue ordering."""
    return digest(('deferred wave package '+name).encode())


def chunks(data, size):
    """Split only exact fixed-width authored dependency/root dictionaries."""
    assert len(data) % size == 0
    return [data[index:index+size] for index in range(0, len(data), size)]


def inputs(parent, initial, slot, cycle, reports, *, gas_limits=None):
    """Hold A pending while B→C→D→E become available, or admit a genuinely unresolved A↔B cycle."""
    specifications = []
    if slot == 3:
        specifications = [('A', 0, 42, ['B'] if cycle else [], []), ('B', 1, 99, ['A'], [])]
    elif not cycle and slot in (4, 5, 6):
        specifications = {4: [('C', 1, 99, ['A', 'B'], [])],
                          5: [('D', 1, 99, [], ['C'])],
                          6: [('E', 1, 99, ['B', 'D'], ['B'])]}[slot]
    gs = []
    for name, core, sid, prerequisites, lookups in specifications:
        # Segment roots are independently authored with the referenced package, never observed state.
        lookup = b''.join(package(key)+digest(package(key)+b'exports') for key in sorted(lookups, key=package))
        item = pipeline.guarantee(parent, initial, core, slot, package=package(name), service=sid,
                                  prerequisites=b''.join(sorted(package(key) for key in prerequisites)), lookup=lookup,
                                  accumulation_gas=100000 if gas_limits is None else gas_limits[name])
        assert package(name) not in reports
        reports[package(name)] = item['layout']
        gs.append(item)
    count, bits = (0, 0)
    if cycle and slot == 4: count, bits = 5, 3
    elif not cycle and slot in (4, 5, 6): count, bits = 5, 2
    elif not cycle and slot == 7: count, bits = 5, 3
    return gs, assurances(parent, count, bits)


def edit(items, completed):
    """The GP E function removes completed reports and subtracts their identities from dependencies."""
    return [(wire, dependencies-completed) for wire, dependencies in items if wire[:32] not in completed]


def plan(parent, mode, slot, ass, reports):
    """Calculate immediate priority, four dependency waves, affordable batches and posterior ready rows."""
    assigned = pending(parent[chapter_key(10)])
    votes = [sum(bool(item['bits'] & (1 << core)) for item in ass) for core in range(2)]
    available = [assigned[core]['guarantee']['report'] for core in range(2)
                 if assigned[core] is not None and votes[core] >= 5]
    history = {key for row in pipeline.accumulated(parent[chapter_key(15)]) for key in chunks(row, 32)}
    rows = [[(wire, set(chunks(dependencies, 32))) for wire, dependencies in row]
            for row in ready(parent[chapter_key(14)])]
    immediate, deferred = [], []
    for wire in available:
        value = reports[wire[:32]]
        dependencies = set(chunks(value['prerequisites'], 32))|{pair[:32] for pair in chunks(value['lookup'], 64)}
        if not dependencies: immediate.append(wire)
        elif wire[:32] not in history: deferred.extend(edit([(wire, dependencies)], history))
    position = slot % 12
    waiting = [item for row in rows[position:]+rows[:position] for item in row]+deferred
    waiting = edit(waiting, {wire[:32] for wire in immediate})
    queue, waves = list(immediate), []
    while True:
        wave = [wire for wire, dependencies in waiting if not dependencies]
        if not wave: break # A cycle or genuinely unresolved dependency stops Q without inventing progress.
        waves.append([wire[:32].hex() for wire in wave]); queue.extend(wave)
        before = len(waiting)
        waiting = edit(waiting, {wire[:32] for wire in wave})
        assert len(waiting) < before # Each finite wave removes at least one actual report.
    remaining, processed, batches, prefixes, budget = list(queue), [], [], [], 300000
    while remaining:
        count, declared = 0, 0
        for wire in remaining:
            cost = sum(item[3] for item in reports[wire[:32]]['digests'])
            if declared+cost > budget: break # Only a whole affordable prefix is selected.
            declared += cost; count += 1
        if not count: break # Unaffordable queued reports remain pending rather than becoming processed history.
        batch = remaining[:count]; group = {}
        for wire in batch:
            for item in reports[wire[:32]]['digests']: group[item[0]] = group.get(item[0], 0)+1
        batches.append(group); prefixes.append([wire[:32].hex() for wire in batch]); processed.extend(batch)
        consumed = sum(22 if sid == 42 else pipeline.guest_gas(mode) for sid in group)
        assert consumed <= declared <= budget
        budget -= consumed; remaining = remaining[count:]
    selected = {wire[:32] for wire in processed}
    posterior = [edit(row, selected) for row in rows]
    posterior[position] = edit(deferred, selected) # Consecutive time expires exactly the current ring row.
    encoded = [[(wire, b''.join(sorted(dependencies))) for wire, dependencies in row] for row in posterior]
    return dict(available=available, processed=processed, batches=batches, ready=encoded,
                reports=reports, waves=waves, prefixes=prefixes, remaining_gas=budget)


def expected_observations(check_frozen=True):
    """Generate every original, signed child and full successor before any native execution."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert fixture['base_fixture_sha256'] == hashlib.sha256(pipeline.FIXTURE.read_bytes()).hexdigest()
    requests, lines, roots, hashes, plans = [], [], [], [], []
    invocations = processed_count = 0
    for mode, cycle in CASES:
        initial = pipeline.original(mode); parent = dict(initial); reports = {}
        roots.append([]); hashes.append([]); plans.append([])
        requests.append('C '+str(pipeline.MODES.index(mode)))
        lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in range(2, 9):
            gs, ass = inputs(parent, initial, slot, cycle, reports)
            projection = plan(parent, mode, slot, ass, reports)
            child, parent = pipeline.advance(parent, initial, mode, slot, gs, ass, plan=projection)
            encoded = checkpoint(list(parent.items()))
            requests.append('B '+body(gs, ass)[0].hex()); lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex())
            hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            plans[-1].append({key: projection[key] for key in ('waves', 'prefixes', 'remaining_gas')})
            invocations += sum(len(group) for group in projection['batches'])
            processed_count += len(projection['processed'])
    if check_frozen:
        assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
        assert plans == fixture['plans']
    return requests, lines, dict(transitions=49, chains=7, guest_executions=invocations,
                                processed_reports=processed_count, roots=roots,
                                checkpoint_sha256=hashes, plans=plans)
