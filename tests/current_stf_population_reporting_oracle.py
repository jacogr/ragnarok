# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP reporting with six/nine/six populations, quorum-before-clear and current erasure widths."""
import copy
import hashlib
import json
from pathlib import Path
import current_stf_epoch_oracle as epoch
import current_stf_population_oracle as population
import current_stf_epoch_reporting_oracle as epoch_reporting
import current_stf_reporting_oracle as reporting
from current_stf_oracle import history, checkpoint, tree
from current_stf_verdict_oracle import signed
from state_layout_oracle import chapter_key, digest
from state_history_oracle import wire as history_wire
from report_oracle import encode as report_wire

FIXTURE = Path(__file__).parent/'fixtures/current-stf-population-reporting.json'
SLOTS = (2, 10, 11, 12, 13, 14, 22, 23, 24, 25)
NAMES = ('prior-quorum-release', 'resize-clears-without-quorum')


def original():
    """Reconstruct the existing original three-core map, then explicitly author entropy and a missing prerequisite."""
    parent = population.original(json.loads(population.FIXTURE.read_text()))
    parent[chapter_key(6)] = bytes(32)+b''.join(digest(b'population-reporting-entropy'+bytes([i])) for i in (1, 2, 3))
    blocks, peaks = history(parent[chapter_key(3)])
    blocks[0] = (blocks[0][0], reporting.DEPENDENCY+bytes(32))
    parent[chapter_key(3)] = history_wire((blocks, peaks))
    return parent


def active_after(parent, slot):
    """Epoch crossing promotes the prior pending roster; the configured capacity never substitutes for its count."""
    crossed = slot//12 > int.from_bytes(parent[chapter_key(11)], 'little')//12
    return epoch.consensus(parent[chapter_key(4)])[0] if crossed else epoch.roster(parent[chapter_key(8)])


def guarantee(parent, core, stamp, slot, report_slot):
    """Use current-population erasure shards even when credentials select the smaller/larger previous roster."""
    value = reporting.report(parent, core, stamp, cores=3, shards=len(active_after(parent, slot)))
    blocks, _ = history(parent[chapter_key(3)])
    fixed, lookup = blocks[-1][0], blocks[-2][0]
    root = tree(list(parent.items()))[0]
    value['header'] = value['header'][:104]+fixed[:32]+fixed[96:100]+root+fixed[32:64]+lookup[:32]+lookup[96:100]+lookup[64:96]
    # Keep dependencies recent and unresolved across two epochs without manufacturing accumulated history.
    pairs = next(pairs for _, pairs in reversed(blocks) if pairs)
    value['prerequisites'] = pairs[:32]
    wire = report_wire(value)
    roster, assigned = epoch_reporting.credentials(parent, slot, report_slot)
    indices = [i for i, selected in enumerate(assigned) if selected == core]
    assert len(indices) == 3
    return dict(report=wire, slot=report_slot, layout=value, credentials=[
        (i, signed(epoch.PUBLIC[roster[i][:32]], b'jam_guarantee', digest(wire))[1]) for i in indices])


def validate(parent, slot, guaranteed, assured):
    """Quorum uses prior active count; population change clears assignments independently of available reports."""
    old = reporting.pending(parent[chapter_key(10)], 3, 9)
    prior, posterior = epoch.roster(parent[chapter_key(8)]), active_after(parent, slot)
    anchor = history(parent[chapter_key(3)])[0][-1][0][:32]
    for item in assured:
        assert item['anchor'] == anchor, 'assurance/WrongParent'
        assert item['signature'] == signed(epoch.PUBLIC[prior[item['index']][:32]], b'jam_available', digest(anchor+bytes([item['bits']])))[1], 'assurance/InvalidSignature'
        assert all(not (item['bits'] & (1 << core)) or old[core] is not None for core in range(3)), 'availability/UnassignedCore'
    released = [sum(bool(a['bits'] & (1 << core)) for a in assured) > 2*len(prior)//3 for core in range(3)]
    changed = len(prior) != len(posterior)
    reporters = set()
    for item in guaranteed:
        core = item['layout']['core']
        assert core < len(posterior)//3, 'credential/InactiveCore'
        assert int.from_bytes(item['layout']['header'][68:70], 'little') == len(posterior), 'credential/WrongErasureShards'
        roster, assigned = epoch_reporting.credentials(parent, slot, item['slot'])
        for index, signature in item['credentials']:
            assert index < len(roster), 'credential/InvalidIndex'
            assert assigned[index] == core, 'credential/WrongAssignment'
            assert signature == signed(epoch.PUBLIC[roster[index][:32]], b'jam_guarantee', digest(item['report']))[1], 'credential/InvalidSignature'
            reporters.add(roster[index][32:64])
        occupied = old[core]
        assert occupied is None or changed or released[core] or slot >= occupied['registered']+5, 'assignment/OccupiedCore'
    return old, released, reporters, changed


def advance(parent, slot, guaranteed, assured):
    """Compose Safrole, history, resized statistics, availability and ready-ring equations before native execution."""
    old, released, reporters, changed = validate(parent, slot, guaranteed, assured)
    fixture = json.loads(epoch.FIXTURE.read_text())
    roots = dict(staging=bytes.fromhex(fixture['staging_ring_root']))
    raw, commitment = reporting.body(guaranteed, assured)
    child, result = epoch.successor(parent, slot, [], [], roots, cores=3,
                                   body_override=raw, extrinsic_override=commitment)
    active, previous = epoch.roster(result[chapter_key(8)]), epoch.roster(result[chapter_key(9)])
    selected = {i for i, row in enumerate(active) if row[32:64] in reporters}
    crossed = slot//12 > int.from_bytes(parent[chapter_key(11)], 'little')//12
    result = reporting.apply_reporting(parent, result, slot, guaranteed, assured, old, released,
        reporters=selected, assurance_previous=crossed, cores=3, current_validators=len(active),
        previous_validators=len(previous), population_changed=changed)
    return child, result


def inputs(parent, case, slot):
    """Separate prior quorum availability from unconditional resize clearing at both growth and shrinkage."""
    guaranteed, assured = [], []
    if slot in (10, 12, 23, 24):
        cores = 3 if slot in (12, 23) else 2
        for core in range(cores):
            # At growth only newly active core2 must use the current nine-member roster.
            stamp = slot-1 if case == 1 and slot in (12, 24) and core < 2 else slot
            guaranteed.append(guarantee(parent, core, slot, slot, stamp))
    votes = {11: 4, 12: 5 if case == 0 else 4, 13: 6, 14: 7,
             24: 7 if case == 0 else 6, 25: 5}
    if slot in votes:
        bits = 7 if slot in (13, 14, 24) else 3
        assured = epoch_reporting.assurances(parent, votes[slot], bits)
    return guaranteed, assured


def resign(item, roster):
    """Re-sign altered authored report fields so credential validity does not mask an erasure policy control."""
    item['report'] = report_wire(item['layout'])
    item['credentials'] = [(i, signed(epoch.PUBLIC[roster[i][:32]], b'jam_guarantee', digest(item['report']))[1]) for i, _ in item['credentials']]


def negatives(parent, case, slot, guaranteed, assured):
    """Isolate current erasure widths, inactive cores, selected-roster bounds and prior-roster assurance signatures."""
    probes = []
    if slot in (12, 24):
        altered = copy.deepcopy(guaranteed)
        item = altered[-1]
        roster, _ = epoch_reporting.credentials(parent, slot, item['slot'])
        prior_count = len(epoch.roster(parent[chapter_key(8)]))
        item['layout']['header'] = item['layout']['header'][:68]+prior_count.to_bytes(2, 'little')+item['layout']['header'][70:]
        resign(item, roster)
        probes.append((altered, assured, 'credential/WrongErasureShards'))
        altered_assurances = copy.deepcopy(assured)
        posterior = active_after(parent, slot)
        first = altered_assurances[0]
        first['signature'] = signed(epoch.PUBLIC[posterior[0][:32]], b'jam_available', digest(first['anchor']+bytes([first['bits']])))[1]
        probes.append((guaranteed, altered_assurances, 'assurance/InvalidSignature'))
    if slot == 12:
        altered = copy.deepcopy(guaranteed)
        item = altered[0]; item['slot'] = 11
        item['credentials'] = [(i, signed(i+1, b'jam_guarantee', digest(item['report']))[1]) for i in (6, 7)]
        probes.append((altered, assured, 'credential/InvalidIndex'))
    if slot == 24:
        # Its prior-nine credentials are authentic, but core2 is inactive under the current six.
        altered = copy.deepcopy(guaranteed)
        item = guarantee(parent, 2, 24, 24, 23)
        altered.append(item)
        probes.append((altered, assured, 'credential/InactiveCore'))
    return probes


def expected_observations(check_frozen=True):
    """Freeze every signed block, complete successor and refusal independently of production observations."""
    requests, lines, roots, hashes, refusals = [], [], [], [], []
    for case, name in enumerate(NAMES):
        parent = original(); roots.append([]); hashes.append([])
        requests.append(f'C {name} {parent[chapter_key(3)].hex()} {parent[chapter_key(6)].hex()}')
        lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in SLOTS:
            guaranteed, assured = inputs(parent, case, slot)
            for gs, ass, reason in negatives(parent, case, slot, guaranteed, assured):
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
        assert fixture['population_fixture_sha256'] == hashlib.sha256(population.FIXTURE.read_bytes()).hexdigest()
        assert fixture['epoch_fixture_sha256'] == hashlib.sha256(epoch.FIXTURE.read_bytes()).hexdigest()
        assert evidence == fixture['evidence']
    return requests, lines, evidence
