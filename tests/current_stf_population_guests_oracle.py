# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent report-driven execution, literal host gas and effect selection across six/nine/six rosters."""
import json
from pathlib import Path
import current_stf_population_reporting_oracle as population
import current_stf_epoch_reporting_oracle as rotation
import current_stf_epoch_oracle as epoch
import current_stf_report_guests_oracle as guests
import current_stf_reporting_oracle as reporting
from current_stf_verdict_oracle import signed
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as metadata_parse
from report_oracle import encode as report_wire
from reporting_scenario_oracle import collect

FIXTURE = Path(__file__).parent/'fixtures/current-stf-population-guests.json'
SOURCES = (population.population.FIXTURE, epoch.FIXTURE, guests.BASE)
MODES = ('create', 'panic-rollback', 'checkpoint-panic')
SLOTS = population.SLOTS


def original(mode):
    """Combine authored population globals and complete executable service inputs before calculating the initial root."""
    parent = population.original()
    globals_ = {chapter_key(i) for i in range(1, 17)}
    return {**{k:v for k,v in parent.items() if k in globals_},
            **{k:v for k,v in guests.original(mode).items() if k not in globals_}}


def guarantee(parent, core, slot, sid, *, prerequisite=b''):
    """Select genuine current-roster credentials, executable code and explicit dependency bytes before signing."""
    item = population.guarantee(parent, core, slot, slot, slot)
    layout = item['layout']; layout['prerequisites'] = prerequisite
    row = list(layout['digests'][0]); row[0] = sid
    row[1] = metadata_parse(parent[chapter_service(255, sid)], 105)[0]
    row[3] = 100000; layout['digests'] = [tuple(row)]
    population.resign(item, rotation.credentials(parent, slot, slot)[0])
    return item


def advance(parent, mode, slot, guaranteed, assured, reports, *, processed=None, batches=None, ready=None):
    """Separate prior-roster quorum from resize clearing; execute independent batches and literal guest effects."""
    old, released, reporters, changed = population.validate(parent, slot, guaranteed, assured)
    available = [item['guarantee']['report'] for item, yes in zip(old,released) if item is not None and yes]
    processed = available if processed is None else processed
    if batches is None:
        group = {}
        for wire in processed:
            sid = reports[wire[:32]]['digests'][0][0]; group[sid] = group.get(sid,0)+1
        batches = [group] if group else []
    roots = dict(staging=bytes.fromhex(json.loads(epoch.FIXTURE.read_text())['staging_ring_root']))
    def foundation(raw, commitment, outputs):
        """Safrole/header/history derive independently while binding actual execution outputs into the MMR."""
        return epoch.successor(parent, slot, [], [], roots, cores=3,
            body_override=raw, extrinsic_override=commitment, outputs=outputs)
    active = population.active_after(parent, slot)
    crossed = slot//12 > int.from_bytes(parent[chapter_key(11)],'little')//12
    previous = epoch.roster(parent[chapter_key(8 if crossed else 9)])
    indices = {i for i,row in enumerate(active) if row[32:64] in reporters}
    plan = dict(processed=processed, available=available, batches=batches, foundation=foundation,
                ready=[[] for _ in range(12)] if ready is None else ready, reports=reports)
    return guests.advance(parent, parent, mode, slot, guaranteed, assured, plan=plan,
        core_count=3, current_count=len(active), previous_count=len(previous),
        prior_count=len(epoch.roster(parent[chapter_key(8)])), reporter_indices=indices, population_changed=changed)


def cases():
    """Each mode releases pre-boundary reports, batches three services and resumes execution after shrinkage."""
    result = []
    for mode in MODES:
        parent = original(mode); initial = dict(parent); reports = {}; steps = []
        for slot in SLOTS:
            guaranteed = []
            if slot in (10,12,23,24):
                for core in range(3 if slot in (12,23) else 2):
                    sid = 99 if slot in (12,23) or core == 1 else 42
                    item = guarantee(parent, core, slot, sid); guaranteed.append(item)
                    reports[item['report'][:32]] = item['layout']
            count = {12:5,13:7,24:7,25:5}.get(slot,0)
            bits = 7 if slot in (13,24) else 3
            assured = rotation.assurances(parent,count,bits) if count else []
            child,after = advance(parent, mode, slot, guaranteed, assured, reports)
            steps.append((child,after,[])); parent=after
        result.append(dict(name=mode,initial=initial,steps=steps))
    return result


def expected_observations(check_frozen=True):
    """Freeze independent roots and complete maps before any native execution."""
    return collect(cases(), FIXTURE, SOURCES, check_frozen)
