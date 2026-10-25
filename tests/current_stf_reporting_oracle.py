# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map guarantee/assurance admission, availability and unresolved ready-ring cases."""
import copy
import hashlib
import json
from pathlib import Path
from functools import cache
from current_stf_oracle import (FIXTURE as BASE, Reader, decode_checkpoint, history, authored_child,
                                advance_no_reports, checkpoint, tree)
from current_stf_epoch_oracle import roster
from current_stf_verdict_oracle import signed
from state_layout_oracle import chapter_key, chapter_service, digest
from state_history_oracle import wire as history_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT
from state_accounts_oracle import parse as metadata_parse
from state_workqueues_oracle import wire as ready_wire
from state_availability_oracle import wire as availability_wire, single_decode
from guarantees_oracle import wire as guarantees_wire
from report_oracle import encode as report_wire, decode as report_decode
from report_fixtures import validate_provider
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-reporting.json'
DEPENDENCY = digest(b'authored known but unaccumulated package')
NAMES = ('quorum-release-and-replacement', 'previous-rotation-and-timeout')


def original():
    """Add one known recent package to an unchanged complete original map, without claiming it accumulated."""
    source = json.loads(BASE.read_text())
    parent = decode_checkpoint(bytes.fromhex(source['cases'][-1]['parent_checkpoint']))
    assert len(parent) == 30
    blocks, peaks = history(parent[chapter_key(3)])
    assert len(blocks) == 1 and not blocks[0][1]
    blocks[0] = (blocks[0][0], DEPENDENCY+bytes(32))
    parent[chapter_key(3)] = history_wire((blocks, peaks))
    return parent


def permutation(seed, count=6):
    """Independent shrinking-swap shuffle uses little-endian words from BLAKE2b(seed||E4(group))."""
    remaining, result = list(range(count)), []
    for index in range(count):
        block = digest(seed+(index//8).to_bytes(4, 'little'))
        at = int.from_bytes(block[4*(index % 8):4*(index % 8)+4], 'little') % len(remaining)
        result.append(remaining[at])
        remaining[at] = remaining[-1]
        remaining.pop()
    return result


def report(parent, core, stamp, *, cores=2, shards=6):
    """Author all report fields, including exact recent/lookup roots and one unresolved known prerequisite."""
    initial = original()
    blocks, _ = history(initial[chapter_key(3)])
    anchor = blocks[0][0][:32]
    root = tree(list(initial.items()))[0]
    code = metadata_parse(parent[chapter_service(255, 42)], 105)[0]
    pool = Reader(parent[chapter_key(1)])
    pools = [pool.take(32*pool.count()) for _ in range(cores)]
    authorizer = pools[core][:32]
    package = digest(f'guaranteed package {stamp} core {core}'.encode())
    header = (package+(100+stamp+core).to_bytes(4, 'little')+digest(package+b'segments')
              +shards.to_bytes(2, 'little')+digest(package+b'exports')+(3+core).to_bytes(2, 'little')
              +anchor+(1).to_bytes(4, 'little')+root+bytes(32)
              +anchor+(1).to_bytes(4, 'little')+root)
    load = (13+core, 2+core, 3+core, 4+core, 5+core)
    value = dict(header=header, prerequisites=DEPENDENCY, core=core, authorizer=authorizer,
                 gas=17+core, auth=b'auth'+bytes([core]), lookup=b'',
                 digests=[(42, code, digest(package+b'payload'), 10, 0, bytes([stamp, core]), load)])
    return value


def guarantee(parent, core, stamp, slot):
    """Sign two or three assigned validators under the selected rotation; report hash alone is signed."""
    value = report(parent, core, stamp)
    wire = report_wire(value)
    seed = parent[chapter_key(6)][64:96]
    indices = [index for index, position in enumerate(permutation(seed))
               if (position//3+(slot % 12)//4) % 2 == core]
    indices = indices[:3 if stamp == 9 else 2]
    return dict(report=wire, slot=slot, credentials=[(index, signed(index+1, b'jam_guarantee', digest(wire))[1])
                                                   for index in indices], layout=value)


def assurances(parent, count, bits):
    """Independently sign the actual parent hash and one canonical fixed two-core bit byte."""
    blocks, _ = history(parent[chapter_key(3)])
    anchor = blocks[-1][0][:32]
    target = digest(anchor+bytes([bits]))
    return [dict(anchor=anchor, bits=bits, index=index,
                 signature=signed(index+1, b'jam_available', target)[1]) for index in range(count)]


def body(guarantees, assurances, preimages=()):
    """Commit only normative guarantee report hashes and assurance raw tuples, with all other families empty."""
    guarantees_part = guarantees_wire(guarantees)
    assurances_part = natural(len(assurances))+b''.join(item['anchor']+bytes([item['bits']])
                        +item['index'].to_bytes(2, 'little')+item['signature'] for item in assurances)
    guaranteed_hashes = natural(len(guarantees))+b''.join(digest(item['report'])+item['slot'].to_bytes(4, 'little')
        +natural(len(item['credentials']))+b''.join(i.to_bytes(2, 'little')+sig for i, sig in item['credentials']) for item in guarantees)
    supplied = natural(len(preimages))+b''.join(sid.to_bytes(4, 'little')+natural(len(value))+value for sid, value in preimages)
    projection = natural(len(preimages))+b''.join(sid.to_bytes(4, 'little')+digest(value) for sid, value in preimages)
    raw = b'\0'+supplied+guarantees_part+assurances_part+bytes(3)
    commitment = digest(digest(b'\0')+digest(projection)+digest(guaranteed_hashes)+digest(assurances_part)+digest(bytes(3)))
    return raw, commitment


def pending(data, cores=2, validators=6):
    """Parse exact C10 records using independent nested report/guarantee framing."""
    source, rows = Reader(data), []
    for _ in range(cores):
        tag = source.take(1)
        assert tag in (b'\0', b'\1')
        if tag == b'\0': rows.append(None)
        else:
            size, value = single_decode(data[source.at:], cores, validators, len(data))
            source.take(size)
            rows.append(dict(guarantee=value, registered=int.from_bytes(source.take(4), 'little')))
    source.done()
    return rows


def ready(data, cores=2):
    """Retain exact full reports and dependency sets in their original twelve ring positions."""
    source, rows = Reader(data), []
    for _ in range(12):
        row = []
        for _ in range(source.count()):
            parsed = report_decode(data[source.at:], cores)
            assert isinstance(parsed, str) and parsed.split()[-1].isdigit(), parsed
            wire = source.take(int(parsed.split()[-1]))
            row.append((wire, source.take(32*source.count())))
        rows.append(row)
    source.done()
    return rows


def validate(parent, slot, guarantees, assured):
    """Independent contextual credential, policy, ancestry and vacancy checks for this authored subset."""
    old = pending(parent[chapter_key(10)])
    blocks, _ = history(parent[chapter_key(3)])
    anchor = blocks[-1][0][:32]
    for item in assured:
        assert item['anchor'] == anchor, 'assurance/WrongParent'
        assert item['signature'] == signed(item['index']+1, b'jam_available', digest(anchor+bytes([item['bits']])))[1], 'assurance/InvalidSignature'
        assert all(not (item['bits'] & (1 << core)) or old[core] is not None for core in range(2)), 'availability/UnassignedCore'
    released = [sum(bool(item['bits'] & (1 << core)) for item in assured) >= 5 for core in range(2)]
    pools = Reader(parent[chapter_key(1)])
    auth = [[pools.take(32) for _ in range(pools.count())] for _ in range(2)]
    for item in guarantees:
        value = item['layout']
        assert int.from_bytes(value['header'][68:70], 'little') == 6, 'credential/WrongErasureShards'
        assert item['slot'] <= slot and slot//4-item['slot']//4 in (0, 1), 'credential/InvalidSlot'
        assigned = permutation(parent[chapter_key(6)][64:96])
        for index, signature in item['credentials']:
            assert (assigned[index]//3+(item['slot'] % 12)//4) % 2 == value['core'], 'credential/WrongAssignment'
            assert signature == signed(index+1, b'jam_guarantee', digest(item['report']))[1], 'credential/InvalidSignature'
        assert value['authorizer'] in auth[value['core']], 'policy/Unauthorized'
        initial = original()
        assert value['header'][140:172] == tree(list(initial.items()))[0], 'anchor/InvalidRecentAnchor'
        assert any(fixed[:32] == value['header'][104:136] and fixed[32:64] == value['header'][172:204]
                   and fixed[64:96] == value['header'][140:172] and fixed[96:100] == value['header'][136:140]
                   for fixed, _ in blocks), 'anchor/InvalidRecentAnchor'
        occupied = old[value['core']]
        assert occupied is None or released[value['core']] or slot >= occupied['registered']+5, 'assignment/OccupiedCore'
    return old, released


def advance(parent, slot, guarantees, assured):
    """Compose the complete no-guest STF after independent report/availability planning."""
    old, released = validate(parent, slot, guarantees, assured)
    raw, commitment = body(guarantees, assured)
    child = authored_child(parent, raw, commitment)
    result = advance_no_reports(parent, child, raw, commitment)
    return child, apply_reporting(parent, result, slot, guarantees, assured, old, released)


def apply_reporting(parent, result, slot, guarantees, assured, old, released, *,
                    reporters=None, assurance_previous=False, cores=2,
                    current_validators=6, previous_validators=6, population_changed=False):
    """Apply reporting equations to an independently calculated base STF; epoch callers select identity/statistics attribution."""
    available = []
    for core, item in enumerate(old):
        if item is not None and released[core]: available.append(item['guarantee']['report'])
        if item is not None and (released[core] or population_changed or slot >= item['registered']+5): old[core] = None
    for item in guarantees:
        old[item['layout']['core']] = dict(guarantee={k: item[k] for k in ('report', 'slot', 'credentials')}, registered=slot)
    result[chapter_key(10)] = availability_wire(old)
    pools, rows = Reader(parent[chapter_key(1)]), []
    for core in range(cores):
        row = [pools.take(32) for _ in range(pools.count())]
        for item in guarantees:
            if item['layout']['core'] == core: row.remove(item['layout']['authorizer'])
        row = (row+[bytes(32)])[-8:]
        rows.append(natural(len(row))+b''.join(row))
    result[chapter_key(1)] = b''.join(rows)
    blocks, peaks = history(result[chapter_key(3)])
    pairs = sorted(item['layout']['header'][:32]+item['layout']['header'][70:102] for item in guarantees)
    blocks[-1] = (blocks[-1][0], b''.join(pairs))
    result[chapter_key(3)] = history_wire((blocks, peaks))
    rows = ready(parent[chapter_key(14)], cores)
    prepared = []
    for wire in available:
        # Appendix C puts the prerequisite sequence immediately after the fixed272-byte report header.
        source = Reader(wire[272:])
        prepared.append((wire, source.take(32*source.count())))
    rows[slot % 12] = prepared
    result[chapter_key(14)] = ready_wire('R', rows)
    assert parent[chapter_key(15)] == result[chapter_key(15)] == bytes(12)
    (current, previous, _, _), _ = statistics_parse(result[chapter_key(13)],
        (cores, current_validators, previous_validators, *DEFAULT[3:]))
    selected = {index for item in guarantees for index, _ in item['credentials']} if reporters is None else reporters
    for index in selected: current[index] = (*current[index][:4], current[index][4]+1, current[index][5])
    for item in assured:
        target = previous if assurance_previous else current
        row = list(target[item['index']]); row[5] += 1; target[item['index']] = tuple(row)
    core_rows = [[0]*8 for _ in range(cores)]
    loads = []
    for item in guarantees:
        value = item['layout']; gas, imports, count, size, exports = value['digests'][0][-1]
        core_rows[value['core']][2:] = [imports, count, size, exports, int.from_bytes(value['header'][32:36], 'little'), gas]
        loads.append((gas, imports, count, size, exports))
    for core in range(cores): core_rows[core][1] = sum(bool(item['bits'] & (1 << core)) for item in assured)
    for wire in available:
        # All available wires were authored here: core follows the fixed header and one prerequisite.
        core = wire[272+1+32]
        segments = int.from_bytes(wire[102:104], 'little')
        core_rows[core][0] = int.from_bytes(wire[32:36], 'little')+4104*((65*segments+63)//64)
    services = []
    if loads:
        sums = [sum(row[i] for row in loads) for i in range(5)]
        services = [(42, 0, 0, len(loads), *sums, 0, 0, 0)]
    result[chapter_key(13)] = statistics_wire((current, previous, core_rows, services))
    return result


def inputs(parent, case, slot):
    """Two consecutive chains isolate quorum replacement versus timeout and previous-rotation credentials."""
    guaranteed, assured = [], []
    if case == 0:
        if slot in (3, 5): guaranteed = [guarantee(parent, core, slot, slot) for core in range(2)]
        if slot == 4: assured = assurances(parent, 4, 3)
        if slot == 5: assured = assurances(parent, 5, 3)
        if slot == 6: assured = assurances(parent, 5, 1)
        if slot == 8: assured = assurances(parent, 5, 2)
    else:
        if slot in (4, 9): guaranteed = [guarantee(parent, core, slot, 3 if slot == 4 else slot) for core in range(2)]
        if slot == 5: assured = assurances(parent, 4, 3)
        if slot == 10: assured = assurances(parent, 5, 1)
        if slot == 11: assured = assurances(parent, 6, 0)
    return guaranteed, assured


def negatives(parent, slot, guarantees, assured):
    """Structurally valid hostile credentials/context are re-sealed; independent validation predicts exact causes."""
    probes = []
    if guarantees:
        changed = copy.deepcopy(guarantees)
        index, signature = changed[-1]['credentials'][-1]
        changed[-1]['credentials'][-1] = (index, bytes([signature[0] ^ 1])+signature[1:])
        probes.append((changed, assured, 'credential/InvalidSignature'))
        changed = copy.deepcopy(guarantees)
        value = changed[-1]['layout']; value['authorizer'] = digest(b'not in any pool'); changed[-1]['report'] = report_wire(value)
        changed[-1]['credentials'] = [(i, signed(i+1, b'jam_guarantee', digest(changed[-1]['report']))[1]) for i, _ in changed[-1]['credentials']]
        probes.append((changed, assured, 'policy/Unauthorized'))
        changed = copy.deepcopy(guarantees)
        item = changed[-1]
        shuffled = permutation(parent[chapter_key(6)][64:96])
        wrong = [i for i, at in enumerate(shuffled) if (at//3+(item['slot'] % 12)//4) % 2 != item['layout']['core']][:2]
        item['credentials'] = [(i, signed(i+1, b'jam_guarantee', digest(item['report']))[1]) for i in wrong]
        probes.append((changed, assured, 'credential/WrongAssignment'))
        changed = copy.deepcopy(guarantees)
        item = changed[-1]
        value = item['layout']
        value['header'] = value['header'][:140]+bytes([value['header'][140] ^ 1])+value['header'][141:]
        item['report'] = report_wire(value)
        item['credentials'] = [(i, signed(i+1, b'jam_guarantee', digest(item['report']))[1]) for i, _ in item['credentials']]
        probes.append((changed, assured, 'anchor/InvalidRecentAnchor'))
    if assured:
        changed = copy.deepcopy(assured)
        changed[-1]['signature'] = bytes(64)
        probes.append((guarantees, changed, 'assurance/InvalidSignature'))
        changed = copy.deepcopy(assured)
        for item in changed:
            item['anchor'] = digest(b'wrong parent')
            item['signature'] = signed(item['index']+1, b'jam_available', digest(item['anchor']+bytes([item['bits']])))[1]
        probes.append((guarantees, changed, 'assurance/WrongParent'))
        initial_hash = history(original()[chapter_key(3)])[0][0][0][:32]
        still_recent = any(fixed[:32] == initial_hash for fixed, _ in history(parent[chapter_key(3)])[0])
        if not guarantees and still_recent:
            # A valid new package cannot replace a live assignment after insufficient/zero-bit assurances.
            for core, item in enumerate(pending(parent[chapter_key(10)])):
                votes = sum(bool(value['bits'] & (1 << core)) for value in assured)
                if item is not None and votes < 5 and slot < item['registered']+5:
                    probes.append(([guarantee(parent, core, 40+slot, slot)], assured, 'assignment/OccupiedCore'))
                    break
    if slot == 2:
        probes.append(([], assurances(parent, 1, 1), 'availability/UnassignedCore'))
    return probes


def expected_observations(check_frozen=True):
    """Generate all expected blocks/maps and negative verdicts before native compilation or execution."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert hashlib.sha256(BASE.read_bytes()).hexdigest() == fixture['base_fixture_sha256']
    initial = original()
    requests, lines, roots, hashes, refusals = [], [], [], [], []
    for case in range(2):
        parent = dict(initial); roots.append([]); hashes.append([])
        requests.append(f"C {NAMES[case]} {parent[chapter_key(3)].hex()}")
        lines.append('P '+checkpoint(list(parent.items())).hex())
        for slot in range(2, 12):
            guaranteed, assured = inputs(parent, case, slot)
            for gs, ass, reason in negatives(parent, slot, guaranteed, assured):
                try: validate(parent, slot, gs, ass)
                except AssertionError as error: assert str(error) == reason, (str(error), reason)
                else: raise AssertionError('negative accepted')
                requests.append(f"N {body(gs, ass)[0].hex()} {reason}"); lines.append('N '+reason); refusals.append(reason)
            wire, parent = advance(parent, slot, guaranteed, assured)
            requests.append('B '+body(guaranteed, assured)[0].hex())
            encoded = checkpoint(list(parent.items()))
            lines.extend(('B '+wire.hex(), 'O '+encoded.hex()))
            roots[-1].append(tree(list(parent.items()))[0].hex()); hashes[-1].append(hashlib.sha256(encoded).hexdigest())
    if check_frozen:
        assert roots == fixture['successor_roots'] and hashes == fixture['successor_checkpoint_sha256']
        assert refusals == fixture['refusals']
    return requests, lines, dict(transitions=20, chains=2, roots=roots, checkpoint_sha256=hashes,
                                 refusals=refusals, ed25519_provider=validate_provider())
