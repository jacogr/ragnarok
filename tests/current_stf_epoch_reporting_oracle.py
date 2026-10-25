# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent epoch/rotation credentials, prior-roster assurances and complete-map reporting equations."""
import copy
import hashlib
import json
from pathlib import Path
import current_stf_epoch_oracle as epoch
import current_stf_reporting_oracle as reporting
from current_stf_oracle import decode_checkpoint, history, checkpoint, tree
from current_stf_verdict_oracle import signed
from report_oracle import encode as report_wire
from state_layout_oracle import chapter_key, digest
from state_history_oracle import wire as history_wire

FIXTURE = Path(__file__).parent/'fixtures/current-stf-epoch-reporting.json'
SLOTS = (2, 10, 11, 12, 13, 14, 15, 16, 17)
NAMES = ('current-epoch-credentials', 'previous-epoch-credentials')


def original():
    """Use the existing original distinct-roster map with one explicitly authored unresolved recent package."""
    source = json.loads(epoch.FIXTURE.read_text())
    parent = decode_checkpoint(bytes.fromhex(source['parent_checkpoint']))
    epoch.validate_parent(parent)
    parent[chapter_key(6)] = bytes(32)+b''.join(digest(b'epoch-reporting-entropy'+bytes([i])) for i in (1, 2, 3))
    blocks, peaks = history(parent[chapter_key(3)])
    blocks[0] = (blocks[0][0], reporting.DEPENDENCY+bytes(32))
    parent[chapter_key(3)] = history_wire((blocks, peaks))
    return parent


def credentials(parent, slot, report_slot):
    """Derive the selected roster and historical entropy from GP priorassignments, without native assignments."""
    prior_slot = int.from_bytes(parent[chapter_key(11)], 'little')
    crossed = slot//12 > prior_slot//12
    active = epoch.consensus(parent[chapter_key(4)])[0] if crossed else epoch.roster(parent[chapter_key(8)])
    previous = epoch.roster(parent[chapter_key(8 if crossed else 9)])
    entropy = [parent[chapter_key(6)][i:i+32] for i in range(0, 128, 32)]
    posterior = entropy[:3] if crossed else entropy[1:]
    assert report_slot <= slot and slot//4-report_slot//4 in (0, 1), 'credential/InvalidSlot'
    last_epoch = report_slot//4 != slot//4 and (slot-4)//12 != slot//12
    roster = previous if last_epoch else active
    seed = posterior[2 if last_epoch else 1]
    positions = reporting.permutation(seed, len(roster))
    return roster, [(position//3+(report_slot % 12)//4) % 2 for position in positions]


def guarantee(parent, core, stamp, slot, report_slot):
    """Author a recent parent-root anchor and sign precisely the selected roster's fixture Ed25519 keys."""
    value = reporting.report(parent, core, stamp)
    fixed = history(parent[chapter_key(3)])[0][-1][0]
    root = tree(list(parent.items()))[0]
    anchor, bag, time = fixed[:32], fixed[32:64], fixed[96:100]
    lookup = history(parent[chapter_key(3)])[0][-2][0]
    value['header'] = value['header'][:104]+anchor+time+root+bag+lookup[:32]+lookup[96:100]+lookup[64:96]
    wire = report_wire(value)
    roster, assigned = credentials(parent, slot, report_slot)
    indices = [index for index, selected in enumerate(assigned) if selected == core][:2]
    return dict(report=wire, slot=report_slot, layout=value, credentials=[
        (i, signed(epoch.PUBLIC[roster[i][:32]], b'jam_guarantee', digest(wire))[1]) for i in indices])


def assurances(parent, count, bits):
    """Assurance credentials always use the prior active roster, including at an epoch crossing."""
    roster = epoch.roster(parent[chapter_key(8)])
    anchor = history(parent[chapter_key(3)])[0][-1][0][:32]
    return [dict(anchor=anchor, bits=bits, index=i,
                 signature=signed(epoch.PUBLIC[roster[i][:32]], b'jam_available', digest(anchor+bytes([bits])))[1])
            for i in range(count)]


def validate(parent, slot, guaranteed, assured):
    """Independently require selected keys/assignments, prior assurance keys and post-assurance vacancy."""
    old = reporting.pending(parent[chapter_key(10)])
    anchor = history(parent[chapter_key(3)])[0][-1][0][:32]
    roster = epoch.roster(parent[chapter_key(8)])
    for item in assured:
        assert item['anchor'] == anchor, 'assurance/WrongParent'
        assert item['signature'] == signed(epoch.PUBLIC[roster[item['index']][:32]], b'jam_available', digest(anchor+bytes([item['bits']])))[1], 'assurance/InvalidSignature'
        assert all(not (item['bits'] & (1 << core)) or old[core] is not None for core in range(2)), 'availability/UnassignedCore'
    released = [sum(bool(a['bits'] & (1 << core)) for a in assured) > 2*len(roster)//3 for core in range(2)]
    reporters = set()
    for item in guaranteed:
        selected, assigned = credentials(parent, slot, item['slot'])
        for index, signature in item['credentials']:
            assert assigned[index] == item['layout']['core'], 'credential/WrongAssignment'
            secret = epoch.PUBLIC[selected[index][:32]]
            assert signature == signed(secret, b'jam_guarantee', digest(item['report']))[1], 'credential/InvalidSignature'
            reporters.add(selected[index][32:64])
        occupied = old[item['layout']['core']]
        assert occupied is None or released[item['layout']['core']] or slot >= occupied['registered']+5, 'assignment/OccupiedCore'
    return old, released, reporters


def advance(parent, slot, guaranteed, assured):
    """Compose independent Safrole/header and reporting equations, mapping reporters by key after rotation."""
    old, released, reporters = validate(parent, slot, guaranteed, assured)
    fixture = json.loads(epoch.FIXTURE.read_text())
    roots = dict(staging=bytes.fromhex(fixture['staging_ring_root']))
    raw, commitment = reporting.body(guaranteed, assured)
    child, result = epoch.successor(parent, slot, [], [], roots, body_override=raw, extrinsic_override=commitment)
    active = epoch.roster(result[chapter_key(8)])
    indices = {i for i, record in enumerate(active) if record[32:64] in reporters}
    crossed = slot//12 > int.from_bytes(parent[chapter_key(11)], 'little')//12
    result = reporting.apply_reporting(parent, result, slot, guaranteed, assured, old, released,
                                      reporters=indices, assurance_previous=crossed)
    return child, result


def inputs(parent, case, slot):
    """Release and replace both cores at the crossing and first later rotation, preserving unresolved dependencies."""
    guaranteed, assured = [], []
    if slot in (10, 12, 16):
        report_slot = slot if case == 0 else slot-1
        guaranteed = [guarantee(parent, core, slot, slot, report_slot) for core in range(2)]
    if slot in (11, 13): assured = assurances(parent, 4, 3)
    if slot in (12, 14, 17): assured = assurances(parent, 5, 3)
    return guaranteed, assured


def negatives(parent, slot, guaranteed, assured):
    """Wrong roster signatures, wrong assignments and stale rotations are independently classified before native sealing."""
    probes = []
    if guaranteed:
        altered = copy.deepcopy(guaranteed)
        item = altered[-1]
        roster, assigned = credentials(parent, slot, item['slot'])
        # An authentic signature from a different fixture key must not satisfy the selected roster/index.
        item['credentials'] = [(i, signed(epoch.PUBLIC[roster[(i+1) % 6][:32]], b'jam_guarantee', digest(item['report']))[1]) for i, _ in item['credentials']]
        probes.append((altered, assured, 'credential/InvalidSignature'))
        altered = copy.deepcopy(guaranteed)
        item = altered[-1]
        wrong = [i for i, core in enumerate(assigned) if core != item['layout']['core']][:2]
        item['credentials'] = [(i, signed(epoch.PUBLIC[roster[i][:32]], b'jam_guarantee', digest(item['report']))[1]) for i in wrong]
        probes.append((altered, assured, 'credential/WrongAssignment'))
        altered = copy.deepcopy(guaranteed)
        altered[-1]['slot'] = 4*(slot//4-1)-1
        probes.append((altered, assured, 'credential/InvalidSlot'))
    if assured:
        altered = copy.deepcopy(assured)
        roster = epoch.roster(parent[chapter_key(8)])
        item = altered[-1]
        item['signature'] = signed(epoch.PUBLIC[roster[(item['index']+1) % 6][:32]], b'jam_available', digest(item['anchor']+bytes([item['bits']])))[1]
        probes.append((guaranteed, altered, 'assurance/InvalidSignature'))
    return probes


def expected_observations(check_frozen=True):
    """Freeze expected blocks, every complete map and exact refusals before native compilation/execution."""
    requests, lines, roots, hashes, refusals = [], [], [], [], []
    for case, name in enumerate(NAMES):
        parent = original(); roots.append([]); hashes.append([])
        requests.append(f'C {name} {parent[chapter_key(3)].hex()} {parent[chapter_key(6)].hex()}')
        lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in SLOTS:
            guaranteed, assured = inputs(parent, case, slot)
            for gs, ass, reason in negatives(parent, slot, guaranteed, assured):
                try: validate(parent, slot, gs, ass)
                except AssertionError as failure: assert str(failure) == reason, (str(failure), reason)
                else: raise AssertionError('negative accepted')
                requests.append(f'N {slot} {reporting.body(gs, ass)[0].hex()} {reason}')
                lines.append('N '+reason); refusals.append(reason)
            child, parent = advance(parent, slot, guaranteed, assured)
            encoded = checkpoint(list(parent.items()))
            requests.append(f'B {slot} {reporting.body(guaranteed, assured)[0].hex()}')
            lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex())
            hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    evidence = dict(transitions=len(SLOTS)*len(NAMES), chains=len(NAMES), roots=roots,
                    checkpoint_sha256=hashes, refusals=refusals)
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['epoch_fixture_sha256'] == hashlib.sha256(epoch.FIXTURE.read_bytes()).hexdigest()
        assert evidence == fixture['evidence']
    return requests, lines, evidence
