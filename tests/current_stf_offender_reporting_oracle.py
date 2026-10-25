# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent offender exclusion, assurance eligibility, dispute cancellation and delayed roster nulling."""
import copy
import json
from pathlib import Path
import current_stf_population_reporting_oracle as population
import current_stf_epoch_reporting_oracle as rotation
import current_stf_epoch_oracle as epoch
import current_stf_reporting_oracle as reporting
import current_stf_verdict_oracle as verdict
from current_stf_oracle import checkpoint, tree
from state_layout_oracle import chapter_key, digest
from state_availability_oracle import wire as availability_wire
from disputes_oracle import wire as dispute_wire
from reporting_scenario_oracle import collect

FIXTURE = Path(__file__).parent/'fixtures/current-stf-offender-reporting.json'
SOURCES = (population.population.FIXTURE, epoch.FIXTURE)
SLOTS = (2, 10, 11, 12, 13, 16, 17, 18, 23, 24, 25)


def post_disputes(parent, value, marker=None):
    """Cancel only bad/wonky report hashes before assurances and include all posterior offenders in Phi."""
    judgments, marks, removed = verdict.plan(parent, value, marker)
    working = dict(parent); working[chapter_key(5)] = judgments
    old = reporting.pending(parent[chapter_key(10)], 3, 9)
    for i, item in enumerate(old):
        if item is not None and digest(item['guarantee']['report']) in removed: old[i] = None
    working[chapter_key(10)] = availability_wire(old)
    return working, marks, verdict.sets(judgments)[3]


def eligible(parent, slot, report_slot, offenders):
    """Keep assignment positions/populations fixed while excluding null/Phi identities from signature authorship."""
    roster, assigned = rotation.credentials(parent, slot, report_slot)
    return [core for core in range(len(population.active_after(parent, slot))//3)
            if sum(selected == core and roster[i][:32] in epoch.PUBLIC and roster[i][32:64] not in offenders
                   for i, selected in enumerate(assigned)) >= 2]


def assurances(parent, count, bits):
    """Actual prior active identities can assure even after an offence, while null records have no signing secret."""
    roster = epoch.roster(parent[chapter_key(8)])
    anchor = population.history(parent[chapter_key(3)])[0][-1][0][:32]
    indices = [i for i, record in enumerate(roster) if record[:32] in epoch.PUBLIC][:count]
    assert len(indices) == count
    return [dict(anchor=anchor, bits=bits, index=i, signature=verdict.signed(epoch.PUBLIC[roster[i][:32]],
        b'jam_available', digest(anchor+bytes([bits])))[1]) for i in indices]


def validate(parent, slot, gs, assured, disputes, marker=None):
    """Verify independently ordered dispute/assurance/admission checks; Phi changes keys rather than core positions."""
    working, marks, offenders = post_disputes(parent, disputes, marker)
    result = population.validate(working, slot, gs, assured)
    for item in gs:
        roster, _ = rotation.credentials(parent, slot, item['slot'])
        assert all(roster[i][32:64] not in offenders for i, _ in item['credentials']), 'credential/InvalidSignature'
    return working, marks, offenders, result


def block(parent, slot, gs, assured, disputes, marker=None):
    """Author a genuine signed block even for refused bodies; no native signer is consulted."""
    _, marks, _ = post_disputes(parent, disputes)
    marks = marks if marker is None else marker
    raw, commitment = reporting.body(gs, assured, disputes=dispute_wire(disputes))
    roots = dict(staging=bytes.fromhex(json.loads(population.population.FIXTURE.read_text())['filtered_staging_ring_root']))
    return epoch.successor(parent, slot, [], [], roots, cores=3, new_offenders=marks,
        body_override=raw, extrinsic_override=commitment)


def advance(parent, slot, gs, assured, disputes):
    """Compose all complete chapters from original-parent equations and post-judgment availability."""
    working, marks, offenders, (old, released, reporters, changed) = validate(parent, slot, gs, assured, disputes)
    wire, result = block(parent, slot, gs, assured, disputes)
    result[chapter_key(5)] = working[chapter_key(5)]
    active, previous = epoch.roster(result[chapter_key(8)]), epoch.roster(result[chapter_key(9)])
    selected = {i for i, row in enumerate(active) if row[32:64] in reporters}
    crossed = slot//12 > int.from_bytes(parent[chapter_key(11)], 'little')//12
    result = reporting.apply_reporting(working, result, slot, gs, assured, old, released,
        reporters=selected, assurance_previous=crossed, cores=3, current_validators=len(active),
        previous_validators=len(previous), population_changed=changed)
    return wire, result


def inputs(parent, case, slot):
    """Two offence timings compose prior-roster assurances, filtered guarantees and later cancellation/replacement."""
    disputes = verdict.payload()
    if slot == (11 if case == 0 else 12): disputes = verdict.payload(culprits=[verdict.culprit(6, bytes(32))])
    if slot == 17:
        target_core = next(core for core in eligible(parent, slot, slot,
            verdict.sets(parent[chapter_key(5)])[3]+[verdict.signed(7, b'jam_valid', bytes(32))[0]]) if core in (0, 1, 2))
        report = reporting.pending(parent[chapter_key(10)], 3, 9)[target_core]['guarantee']['report']
        target = digest(report)
        disputes = verdict.payload([verdict.verdict(parent, target, 1, 0)], faults=[verdict.fault(7, target, True)])
    working, _, offenders = post_disputes(parent, disputes)
    gs, ass = [], []
    if slot in (10, 12, 16, 23, 24):
        for core in eligible(working, slot, slot, offenders):
            previous = slot-1
            use_previous = case == 1 and slot in (12, 24) and core in eligible(working, slot, previous, offenders)
            gs.append(population.guarantee(parent, core, slot, slot, previous if use_previous else slot, offenders=offenders))
    if slot == 17:
        cancelled = next(i for i, item in enumerate(reporting.pending(working[chapter_key(10)], 3, 9)) if item is None)
        gs = [population.guarantee(parent, cancelled, slot, slot, slot, offenders=offenders)]
    bits = sum(1 << i for i, item in enumerate(reporting.pending(working[chapter_key(10)], 3, 9)) if item is not None)
    votes = {12:6, 13:7, 17:7, 18:7, 24:7, 25:5}
    if slot in votes and bits: ass = assurances(parent, votes[slot], bits)
    return gs, ass, disputes


def negatives(parent, slot, gs, ass, disputes):
    """All rejected inputs are fully re-sealed and independently classified without granting a partial successor."""
    result = []
    _, marks, offenders = post_disputes(parent, disputes)
    if marks:
        result.append((gs, ass, disputes, [], 'dispute/InvalidMarker'))
        changed = copy.deepcopy(disputes)
        section = 'culprits' if changed['culprits'] else 'faults'
        changed[section][-1]['signature'] = bytes(64)
        result.append((gs, ass, changed, marks, 'dispute/InvalidSignature'))
    if slot == 17:
        changed = assurances(parent, 7, 7)
        result.append((gs, changed, disputes, marks, 'availability/UnassignedCore'))
    if gs and offenders:
        changed = copy.deepcopy(gs)
        for item in changed:
            roster, assigned = rotation.credentials(parent, slot, item['slot'])
            excluded = [i for i, row in enumerate(roster) if row[32:64] in offenders and assigned[i] == item['layout']['core'] and row[:32] in epoch.PUBLIC]
            if excluded:
                indices = sorted({excluded[0], next(i for i, _ in item['credentials'] if i != excluded[0])})
                item['credentials'] = [(i, verdict.signed(epoch.PUBLIC[roster[i][:32]], b'jam_guarantee', digest(item['report']))[1]) for i in indices]
                result.append((changed, ass, disputes, marks, 'credential/InvalidSignature')); break
    return result


def cases():
    """Expected parents recurse only through independently calculated successors, never observed maps."""
    result = []
    for case in range(2):
        parent = population.original()
        parent[chapter_key(6)] = bytes(32)+b''.join(digest(b'offender-reporting-eta'+bytes([i])) for i in (1, 2, 3))
        original = dict(parent); steps = []
        for slot in SLOTS:
            gs, ass, disputes = inputs(parent, case, slot)
            refused = []
            for bad_gs, bad_ass, bad_disputes, marker, reason in negatives(parent, slot, gs, ass, disputes):
                try: validate(parent, slot, bad_gs, bad_ass, bad_disputes, marker)
                except AssertionError as error:
                    actual = str(error)
                    actual = actual if '/' in actual else 'dispute/'+actual
                    assert actual == reason, (actual, reason)
                else: raise AssertionError('negative accepted')
                # Invalid signatures need a valid marker; block construction uses the declared public offender sequence.
                wire, _ = block(parent, slot, bad_gs, bad_ass, disputes, marker)
                if bad_disputes != disputes:
                    raw, commitment = reporting.body(bad_gs, bad_ass, disputes=dispute_wire(bad_disputes))
                    roots = dict(staging=bytes.fromhex(json.loads(population.population.FIXTURE.read_text())['filtered_staging_ring_root']))
                    wire, _ = epoch.successor(parent, slot, [], [], roots, cores=3, new_offenders=marker,
                        body_override=raw, extrinsic_override=commitment)
                refused.append((wire, reason))
            wire, after = advance(parent, slot, gs, ass, disputes)
            steps.append((wire, after, refused)); parent = after
        result.append(dict(name='offence-before-growth' if case == 0 else 'offence-at-growth', initial=original, steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Bind complete maps, exact signed inputs, immutable initial maps and typed refusal sequences."""
    return collect(cases(), FIXTURE, SOURCES, check_frozen)
