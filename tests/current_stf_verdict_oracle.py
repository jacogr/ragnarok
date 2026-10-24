# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map verdict classification, fault evidence, assignment cancellation and epoch selection.

OpenSSL signs public fixture seeds, independently of native dalek. No observed STF output enters
the calculations. The earlier qualified ring commitments remain fixed input witnesses.
"""
import copy
import hashlib
import json
from functools import cache
from pathlib import Path
import current_stf_population_oracle as population
from current_stf_epoch_oracle import successor, roster, PUBLIC
from current_stf_oracle import Reader, checkpoint, tree
from state_layout_oracle import chapter_key, digest
from state_availability_oracle import record, wire as assignments_wire, single_decode
from disputes_oracle import wire as disputes_wire
from report_fixtures import openssl_sign, validate_provider
from test_codec import reference_encode as natural

FIXTURE = Path(__file__).parent/'fixtures/current-stf-verdicts.json'
SLOTS = ((2, 3, 6, 11, 12, 13), (12, 13, 14, 24, 25), (2,))
NAMES = ('mixed-sections-and-cancellation', 'parent-epoch-quorums', 'wonky-cancellation')


@cache
def signed(secret, domain, target):
    """Public scalar identities use Ed25519 seed(10+scalar), with no production signer dependency."""
    return openssl_sign(bytes([secret+10])+bytes(31), domain+target)


def original_assignments():
    """Author three distinct report records; original C10 retains only active cores0/1."""
    result = []
    # These are trusted original C10 inputs, not a claimed predecessor guarantee-admission trace.
    for core in range(3):
        guarantee = record(core)
        guarantee['report'] = digest(b'verdict-original-package'+bytes([core]))+guarantee['report'][32:]
        guarantee['slot'] = 1
        guarantee['credentials'] = [(i, signed(i+1, b'jam_guarantee', digest(guarantee['report']))[1])
                                    for i in range(2)]
        result.append(dict(registered=1, guarantee=guarantee))
    return result


def assignments(data):
    """Parse exact optional guarantee/registration records with the independent nested codec reference."""
    source, result = Reader(data), []
    for _ in range(3):
        tag = source.take(1)
        assert tag in (b'\0', b'\1')
        if tag == b'\0':
            result.append(None)
        else:
            parsed = single_decode(data[source.at:], 3, 9, len(data))
            assert isinstance(parsed, tuple), parsed
            consumed, guarantee = parsed
            source.take(consumed)
            result.append(dict(guarantee=guarantee, registered=int.from_bytes(source.take(4), 'little')))
    source.done()
    assert assignments_wire(result) == data
    return result


def sets(data):
    """Decode all four canonical judgment sets without discarding their original members."""
    source = Reader(data)
    result = [[source.take(32) for _ in range(source.count())] for _ in range(4)]
    source.done()
    assert all(items == sorted(set(items)) for items in result)
    return result


def vote(secret, index, valid, target):
    """A vote binds its exact E2 ordinal and domain to one independently signed report identity."""
    return dict(index=index, vote=valid, signature=signed(secret, b'jam_valid' if valid else b'jam_invalid', target)[1])


def verdict(parent, target, age, positives, count=None):
    """Choose voters from the original parent epoch, including high ordinals absent in a smaller posterior set."""
    epoch = int.from_bytes(parent[chapter_key(11)], 'little')//12
    members = roster(parent[chapter_key(8 if age == epoch else 9)])
    quorum = len(members)*2//3+1 if count is None else count
    indices = list(range(quorum-1))+[len(members)-1] if quorum <= len(members) else list(range(quorum))
    return dict(target=target, age=age, votes=[vote(PUBLIC[members[index][:32]], index, at < positives, target)
                                             for at, index in enumerate(indices)])


def fault(secret, target, valid):
    """Fault validity describes the signed judgment, which must oppose the final good/bad classification."""
    key, signature = signed(secret, b'jam_valid' if valid else b'jam_invalid', target)
    return dict(target=target, vote=valid, key=key, signature=signature)


def culprit(secret, target):
    """A culprit may repeat a fault key across sections; only state-set insertion deduplicates it."""
    key, signature = signed(secret, b'jam_guarantee', target)
    return dict(target=target, key=key, signature=signature)


def payload(verdicts=(), culprits=(), faults=()):
    """Sort each independent extrinsic section canonically, preserving cross-section key repetition."""
    return dict(verdicts=sorted(verdicts, key=lambda item: item['target']),
                culprits=sorted(culprits, key=lambda item: item['key']),
                faults=sorted(faults, key=lambda item: item['key']))


def plan(parent, value, marker=None):
    """Independently apply GP judgments, eligibility, signatures, missing-fault and exact marker rules."""
    judgments = sets(parent[chapter_key(5)])
    epoch = int.from_bytes(parent[chapter_key(11)], 'little')//12
    active, previous = roster(parent[chapter_key(8)]), roster(parent[chapter_key(9)])
    eligible = {row[32:64] for row in active+previous}-set(judgments[3])
    identities = {signed(secret, b'jam_valid', bytes(32))[0]: secret for secret in range(1, 10)}
    good, removed = [], []
    # Classification uses the chosen parent's population, never the ceiling or posterior roster.
    for item in value['verdicts']:
        assert item['age'] == epoch or epoch > 0 and item['age'] == epoch-1, 'InvalidEpoch'
        members = active if item['age'] == epoch else previous
        quorum = len(members)*2//3+1
        assert len(item['votes']) == quorum, 'InvalidQuorum'
        assert all(item['target'] not in group for group in judgments[:3]), 'AlreadyJudged'
        positives = 0
        for judgment in item['votes']:
            assert judgment['index'] < len(members), 'InvalidKey'
            key = members[judgment['index']][32:64]
            domain = b'jam_valid' if judgment['vote'] else b'jam_invalid'
            assert key in identities and judgment['signature'] == signed(identities[key], domain, item['target'])[1], 'InvalidSignature'
            positives += judgment['vote']
        assert positives in (0, quorum, len(members)//3), 'InvalidSplit'
        kind = 0 if positives == quorum else 1 if positives == 0 else 2
        judgments[kind].append(item['target'])
        (good if kind == 0 else removed).append(item['target'])
    offenders, fault_targets = [], []
    # Evidence checks posterior classifications and original eligibility, before any new offender is inserted.
    for section in ('culprits', 'faults'):
        for item in value[section]:
            kind = 1 if section == 'culprits' or item['vote'] else 0
            assert item['target'] in judgments[kind], 'InvalidEvidence'
            assert item['key'] in eligible, 'InvalidKey'
            domain = b'jam_guarantee' if section == 'culprits' else b'jam_valid' if item['vote'] else b'jam_invalid'
            assert item['signature'] == signed(identities[item['key']], domain, item['target'])[1], 'InvalidSignature'
            offenders.append(item['key'])
            if section == 'faults': fault_targets.append(item['target'])
    assert all(target in fault_targets for target in good), 'MissingFault'
    assert marker is None or marker == offenders, 'InvalidMarker'
    judgments[3].extend(offenders)
    encoded = b''.join(natural(len(set(group)))+b''.join(sorted(set(group))) for group in judgments)
    return encoded, offenders, removed


def advance(parent, slot, value, root):
    """Compose independently planned judgments with no-report STF equations, then clear/carry exact C10 records."""
    judgments, marker, removed = plan(parent, value)
    child, result = successor(parent, slot, [], [], dict(staging=root), cores=3,
                              dispute_wire=disputes_wire(value), new_offenders=marker)
    result[chapter_key(5)] = judgments
    retained = assignments(parent[chapter_key(10)])
    resized = len(roster(parent[chapter_key(8)])) != len(roster(result[chapter_key(8)]))
    # Empty assurances make no report available; cancellation and timeout/resize only remove retained assignments.
    for index, item in enumerate(retained):
        if item is not None and (digest(item['guarantee']['report']) in removed
                                 or slot >= item['registered']+5 or resized):
            retained[index] = None
    result[chapter_key(10)] = assignments_wire(retained)
    return child, result


def positive(parent, case, slot, targets):
    """Declare three bounded chains, including same-block and delayed opposing evidence."""
    bad, wonky, good = targets
    extra = lambda label: digest(label.encode())
    if case in (0, 2) and slot == 2:
        return payload([verdict(parent, bad, 0, 0), verdict(parent, wonky, 0, 2), verdict(parent, good, 0, 5)],
                       [culprit(6, bad)], [fault(6, good, False), fault(7, bad, True)])
    if case == 0 and slot == 3:
        return payload(faults=[fault(8, good, False)])
    if case == 1 and slot == 12:
        target = extra('pre-growth bad')
        return payload([verdict(parent, target, 0, 0)], faults=[fault(6, target, True)])
    if case == 1 and slot == 13:
        return payload([verdict(parent, good, 1, 7), verdict(parent, bad, 0, 0), verdict(parent, wonky, 1, 3)],
                       faults=[fault(7, good, False), fault(8, bad, True)])
    if case == 1 and slot == 14:
        return payload([verdict(parent, extra('previous wonky'), 0, 2), verdict(parent, extra('current bad'), 1, 0)],
                       faults=[fault(9, good, False)])
    if case == 1 and slot == 24:
        return payload([verdict(parent, extra('pre-shrink wonky'), 1, 3)])
    return payload()


def negative(parent, case, slot, value, targets):
    """Return structurally valid signed hostile inputs with exact independently predicted disputes reasons."""
    bad, wonky, good = targets
    probes = []
    if (case, slot) in ((0, 2), (1, 13), (1, 24)):
        changed = copy.deepcopy(value)
        changed['verdicts'][0]['votes'].pop()
        probes.append((changed, None, 'InvalidQuorum'))
        changed = copy.deepcopy(value)
        changed['verdicts'][0]['age'] = 8
        probes.append((changed, None, 'InvalidEpoch'))
        changed = copy.deepcopy(value)
        raw = changed['verdicts'][0]['votes'][0]['signature']
        changed['verdicts'][0]['votes'][0]['signature'] = bytes([raw[0] ^ 1])+raw[1:]
        probes.append((changed, None, 'InvalidSignature'))
    if case == 0 and slot == 2:
        changed = copy.deepcopy(value)
        item = next(item for item in changed['verdicts'] if item['target'] == bad)
        item['votes'][0] = vote(1, 0, True, bad)
        probes.append((changed, None, 'InvalidSplit'))
        changed = copy.deepcopy(value)
        changed['faults'] = [item for item in changed['faults'] if item['target'] != good]
        probes.append((changed, None, 'MissingFault'))
        changed = copy.deepcopy(value)
        item = next(item for item in changed['faults'] if item['target'] == good)
        item['signature'] = signed(6, b'jam_valid', good)[1]
        probes.append((changed, None, 'InvalidSignature'))
        probes.append((payload(value['verdicts'], value['culprits'], [fault(6, wonky, True)]), None, 'InvalidEvidence'))
        marker = plan(parent, value)[1]
        probes.extend(((value, marker[:-1], 'InvalidMarker'), (value, list(dict.fromkeys(marker)), 'InvalidMarker')))
    if case == 0 and slot == 3:
        probes.extend(((payload([verdict(parent, bad, 0, 0)]), None, 'AlreadyJudged'),
                       (payload(faults=[fault(6, bad, True)]), None, 'InvalidKey'),
                       (payload(faults=[fault(8, wonky, False)]), None, 'InvalidEvidence')))
    if case == 1 and slot == 13:
        probes.append((payload([verdict(parent, bad, 0, 0, count=6)]), None, 'InvalidQuorum'))
        changed = copy.deepcopy(value)
        item = next(item for item in changed['verdicts'] if item['target'] == bad)
        # Previous ordinal0 names scalar1, whereas posterior active ordinal0 names scalar2.
        item['votes'][0] = vote(2, 0, False, bad)
        probes.append((changed, None, 'InvalidSignature'))
    return probes


def expected_observations(check_frozen=True):
    """Produce signed requests and all complete expected outputs before native execution."""
    fixture = json.loads(FIXTURE.read_text())
    assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
    assert hashlib.sha256(population.FIXTURE.read_bytes()).hexdigest() == fixture['population_fixture_sha256']
    provider = validate_provider()
    original = population.original(json.loads(population.FIXTURE.read_text()))
    retained = original_assignments()
    rho = assignments_wire(retained[:2]+[None])
    assert rho.hex() == fixture['retained_assignments']
    hashes_by_core = [digest(item['guarantee']['report']) for item in retained]
    assert [target.hex() for target in hashes_by_core] == fixture['disputed_report_hashes']
    root = bytes.fromhex(json.loads(population.FIXTURE.read_text())['filtered_staging_ring_root'])
    requests, lines, hashes, roots, refusals = [], [], [], [], []
    for case, slots in enumerate(SLOTS):
        parent = dict(original)
        parent[chapter_key(10)] = bytes(3) if case == 1 else rho
        targets = [hashes_by_core[2], hashes_by_core[0], hashes_by_core[1]] if case == 2 else [hashes_by_core[0], hashes_by_core[2], hashes_by_core[1]]
        requests.append(f"C {NAMES[case]} {parent[chapter_key(10)].hex()}")
        lines.append('P '+checkpoint(list(parent.items())).hex())
        hashes.append([])
        roots.append([])
        for slot in slots:
            value = positive(parent, case, slot, targets)
            for invalid, marker, reason in negative(parent, case, slot, value, targets):
                if marker is None:
                    marker = [item['key'] for section in ('culprits', 'faults') for item in invalid[section]]
                try:
                    plan(parent, invalid, marker)
                except AssertionError as error:
                    assert str(error) == reason, (str(error), reason)
                else:
                    raise AssertionError('negative control accepted')
                requests.append(f"N {slot} {disputes_wire(invalid).hex()} {b''.join(marker).hex() or '-'} {reason}")
                lines.append('N '+reason)
                refusals.append(reason)
            child, parent = advance(parent, slot, value, root)
            marker = [item['key'] for section in ('culprits', 'faults') for item in value[section]]
            requests.append(f"B {slot} {disputes_wire(value).hex()} {b''.join(marker).hex() or '-'}")
            encoded = checkpoint(list(parent.items()))
            hashes[-1].append(hashlib.sha256(encoded).hexdigest())
            roots[-1].append(tree(list(parent.items()))[0].hex())
            lines.extend(('B '+child.hex(), 'O '+encoded.hex()))
    if check_frozen:
        assert hashes == fixture['successor_checkpoint_sha256']
        assert roots == fixture['successor_roots']
        assert refusals == fixture['refusals']
    return requests, lines, dict(transitions=sum(map(len, SLOTS)), chains=len(SLOTS), roots=roots,
                                 checkpoint_sha256=hashes, refusals=refusals, ed25519_provider=provider)
