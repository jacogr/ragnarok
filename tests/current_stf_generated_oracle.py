# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Seeded reachable reporting histories with independent GP successors and single-rule refusals.

Only authored fixtures and mathematical references supply expected states. Native results never
enter generation, continuation, cached histories or frozen evidence. SHA-256 counter draws define
portable scheduling choices; this sampler is deliberately bounded rather than exhaustive.
"""
from copy import deepcopy
import hashlib
from pathlib import Path
import current_stf_population_guests_oracle as guests
import current_stf_population_reporting_oracle as population
import current_stf_epoch_reporting_oracle as credentials
from current_stf_oracle import history, tree
from report_oracle import encode as report_wire
from current_stf_verdict_oracle import signed
from owned_history_cache import owned_histories
from reporting_scenario_oracle import collect
from state_accounts_oracle import parse as metadata
from state_layout_oracle import chapter_key, chapter_service, digest

FIXTURE = Path(__file__).parent/'fixtures/current-stf-generated.json'
SOURCES = (population.FIXTURE, guests.FIXTURE, guests.guests.BASE)
NATIVE_DEFINES = ('lateHistories',)
SEEDS = (1, 2, 7, 42, 2026)
WINDOWS = ((2, 2), (7, 9), (10, 10), (11, 11), (12, 12), (13, 15),
           (19, 21), (22, 22), (23, 23), (24, 24), (25, 27), (29, 31))


def decisions(seed):
    """Generate serializable choices with no dependency on Python's random implementation or state."""
    if type(seed) is not int or not 0 <= seed < 2**32:
        raise ValueError('seed must be an unsigned32-bit integer')
    events = []
    for index, (first, last) in enumerate(WINDOWS):
        # Counter bytes and field positions are the versioned sampler contract, independent of STF code.
        draw = hashlib.sha256(seed.to_bytes(4, 'little')+index.to_bytes(4, 'little')).digest()
        events.append(dict(slot=first+draw[0] % (last-first+1), guarantees=draw[1] & 7,
                           assurances=draw[2] & 7, quorum=draw[3] % 3,
                           voters=draw[4], previous=draw[5] & 1, services=draw[6] & 7))
    return events


def authored_report(parent, slot, core, report_slot, service):
    """Sign a dependency-free report directly; evicted unrelated package history is never a prerequisite."""
    value = guests.reporting.report(parent, core, slot, cores=3,
                                    shards=len(population.active_after(parent, slot)))
    blocks, _ = history(parent[chapter_key(3)])
    fixed, lookup = blocks[-1][0], blocks[-2][0]
    root = tree(list(parent.items()))[0]
    value['header'] = (value['header'][:104]+fixed[:32]+fixed[96:100]+root+fixed[32:64]
                       +lookup[:32]+lookup[96:100]+lookup[64:96])
    value['prerequisites'] = b''
    row = list(value['digests'][0])
    row[0] = service
    row[1] = metadata(parent[chapter_service(255, service)], 105)[0]
    row[3] = 100000
    value['digests'] = [tuple(row)]
    roster, assigned = credentials.credentials(parent, slot, report_slot)
    indices = [index for index, at in enumerate(assigned) if at == core]
    assert 2 <= len(indices) <= 3
    item = dict(report=report_wire(value), slot=report_slot, layout=value,
                credentials=[(index, bytes(64)) for index in indices])
    population.resign(item, roster)
    return item


def inputs(parent, event):
    """Derive legal pending-core choices and independently signed voter subsets from one reachable parent."""
    slot = event['slot']
    old = guests.reporting.pending(parent[chapter_key(10)], 3, 9)
    prior = population.epoch.roster(parent[chapter_key(8)])
    active = population.active_after(parent, slot)
    bits = event['assurances'] & sum(1 << core for core, item in enumerate(old) if item)
    threshold = 2*len(prior)//3
    count = (0, threshold, threshold+1)[event['quorum']] if bits else 0
    all_votes = credentials.assurances(parent, len(prior), bits)
    # Rotate the selected set, then sort wire indices as required by GP assurance ordering.
    indices = sorted((event['voters']+offset) % len(prior) for offset in range(count))
    assured = [all_votes[index] for index in indices]
    released = [count > threshold and bool(bits & (1 << core)) for core in range(3)]
    changed = len(prior) != len(active)
    guaranteed = []
    anchored = len(history(parent[chapter_key(3)])[0]) > 1
    for core in range(len(active)//3):
        # An occupied assignment becomes replaceable only after release, resize or the exact timeout.
        occupied = old[core]
        vacant = occupied is None or released[core] or changed or slot >= occupied['registered']+5
        # Reserve the first retained event for lookup-anchor preparation, including after minimization.
        if anchored and vacant and event['guarantees'] & (1 << core):
            previous = bool(event['previous']) and slot in (12, 24) and core < 2
            report_slot = slot-1 if previous else slot
            sid = 99 if event['services'] & (1 << core) else 42
            guaranteed.append(authored_report(parent, slot, core, report_slot, sid))
    return guaranteed, assured, dict(prior=len(prior), current=len(active), bits=bits,
                                    votes=count, threshold=threshold, released=released,
                                    resized=changed, previous=any(g['slot'] != slot for g in guaranteed))


def negative_inputs(parent, slot, guaranteed, assured):
    """Change one semantic condition, preserving valid outer signatures and all unrelated credentials."""
    probes = []
    if guaranteed:
        bad = deepcopy(guaranteed)
        index, signature = bad[0]['credentials'][0]
        bad[0]['credentials'][0] = (index, signature[:-1]+bytes([signature[-1] ^ 1]))
        probes.append((bad, assured, 'credential/InvalidSignature'))
        bad = deepcopy(guaranteed)
        item = bad[0]
        shards = len(population.active_after(parent, slot))
        wrong = 6 if shards == 9 else 9
        item['layout']['header'] = item['layout']['header'][:68]+wrong.to_bytes(2, 'little')+item['layout']['header'][70:]
        population.resign(item, credentials.credentials(parent, slot, item['slot'])[0])
        probes.append((bad, assured, 'credential/WrongErasureShards'))
    if assured:
        bad = deepcopy(assured)
        signature = bad[0]['signature']
        bad[0]['signature'] = signature[:-1]+bytes([signature[-1] ^ 1])
        probes.append((guaranteed, bad, 'assurance/InvalidSignature'))
        bad = deepcopy(assured)
        first = bad[0]
        first['anchor'] = bytes([first['anchor'][0] ^ 1])+first['anchor'][1:]
        roster = population.epoch.roster(parent[chapter_key(8)])
        secret = population.epoch.PUBLIC[roster[first['index']][:32]]
        first['signature'] = signed(secret, b'jam_available', digest(first['anchor']+bytes([first['bits']])))[1]
        probes.append((guaranteed, bad, 'assurance/WrongParent'))
    return probes


def rejected_block(parent, slot, guaranteed, assured):
    """Sign and commit the actual malformed body without asking the production implementation for a result."""
    import json
    raw, commitment = guests.reporting.body(guaranteed, assured)
    roots = dict(staging=bytes.fromhex(json.loads(population.epoch.FIXTURE.read_text())['staging_ring_root']))
    return population.epoch.successor(parent, slot, [], [], roots, cores=3,
                                     body_override=raw, extrinsic_override=commitment)[0]


def scenario(seed, events=None):
    """Regenerate every parent after any event reduction; no removed block's posterior is retained."""
    sampled = decisions(seed)  # Validate seed type/range even when replay supplies explicit events.
    mode = guests.MODES[seed % len(guests.MODES)]
    selected = sampled if events is None else deepcopy(events)
    if not selected or len(selected) > len(WINDOWS):
        raise ValueError('campaign requires one to twelve ordered events')
    parent = guests.original(mode)
    initial = deepcopy(parent)
    reports, steps, facts = {}, [], []
    for event in selected:
        # Rebuilding inputs from this current reference parent keeps reduced histories reachable.
        slot = event['slot']
        if not int.from_bytes(parent[chapter_key(11)], 'little') < slot <= 31:
            raise ValueError('campaign slots must increase within2..31')
        gs, ass, fact = inputs(parent, event)
        negatives = []
        for bad_gs, bad_ass, reason in negative_inputs(parent, slot, gs, ass):
            try:
                population.validate(parent, slot, bad_gs, bad_ass)
            except AssertionError as failure:
                assert str(failure) == reason, (str(failure), reason)
            else:
                raise AssertionError('independent validator accepted malformed input')
            negatives.append((rejected_block(parent, slot, bad_gs, bad_ass), reason))
        for item in gs:
            reports[item['report'][:32]] = item['layout']
        block, after = guests.advance(parent, mode, slot, gs, ass, reports)
        steps.append((block, after, negatives))
        facts.append(dict(fact, slot=slot, guarantees=len(gs), negative_rules=[r for _, r in negatives]))
        parent = after
    return dict(name='seed-'+str(seed), initial=initial, steps=steps, seed=seed,
                events=selected, facts=facts, mode=mode)


@owned_histories
def cases():
    """Privately cache the fixed regression campaign while returning independent owned histories."""
    return [scenario(seed) for seed in SEEDS]


def expected_observations(check_frozen=True):
    """Bind every expected complete map and invalid block before native compilation or execution."""
    return collect(cases(), FIXTURE, SOURCES, check_frozen)
