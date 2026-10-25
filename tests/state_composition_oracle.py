# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full composition equations over exact chapter extents and typed service fields.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import hashlib
import random
from test_codec import reference_encode as natural
from state_layout_oracle import chapter_key, chapter_service, token, MAX
from state_trie_oracle import tree, reference
from state_service_values_oracle import key as service_key
from state_requests_oracle import wire as history_wire, key as request_key
from state_statistics_oracle import wire as statistics_wire
from state_roots_oracle import published
import state_authorization_oracle as authorization
import state_history_oracle as history
import state_consensus_oracle as consensus
import state_disputes_oracle as disputes
import state_safrole_oracle as safrole
import state_availability_oracle as availability
import state_privileges_oracle as privileges
import state_statistics_oracle as statistics
import state_workqueues_oracle as workqueues
import state_outputs_oracle as outputs

PROFILE = (2, 6, 6, 2)
POLICY = (1_000_000, 8_000_000)


# Minimal authored chapters contain complete shapes; patterned fixed records expose ordering/copy errors.
def chapters():
    roster = natural(6)+bytes(i % 251 for i in range(6*336))
    return [bytes(2), bytes(i % 251 for i in range(2*80*32)), b'\0\0',
        roster+bytes(144)+b'\1'+bytes(64)+b'\0', bytes(4), bytes(range(128)),
        roster, roster, roster, bytes(2), b'\4\3\2\1', bytes(21),
        statistics_wire(([(0,)*6]*6, [(0,)*6]*6, [(0,)*8]*2, [])),
        bytes(2), bytes(2), b'\0']


# Reference capture requires complete extent, keeping child schema failures separate from trailing bytes.
def capture(chapter, data, profile=PROFILE, policy=POLICY):
    cores, current, previous, slots = profile
    items, budget = policy
    if not 2 <= cores <= 341 or slots == 0 or any(n < 6 or n > 3*cores or n % 3 for n in (current, previous)):
        return 'invalidconfig' # Shared profile checks precede raw byte and child policy checks.
    if len(data) > budget:
        return 'limitexceeded' # A valid prefix cannot excuse an oversized externally delimited value.
    decoded = None
    # Child oracles use their established tuple configurations and independent byte equations.
    if chapter in (1, 2):
        decoded = authorization.decode(chapter-1, data, (cores, items, budget))
    elif chapter == 3:
        decoded = history.decode(data, (cores, items, items, items, items, budget))
    elif chapter == 4:
        decoded = consensus.decode(data, (cores, items, budget, slots, items, budget))
    elif chapter == 5:
        decoded = disputes.decode(data, (items, items, budget))
    elif chapter in (6, 11):
        width = 128 if chapter == 6 else 4
        decoded = 'truncated' if len(data) < width else str(width)
    elif chapter in (7, 8, 9):
        decoded = safrole.decode(data, (cores, items, budget))
    elif chapter == 10:
        decoded = availability.decode(data, (cores, max(current, previous), budget, items, budget))
    elif chapter == 12:
        decoded = privileges.decode(data, (cores, items, budget))
    elif chapter == 13:
        decoded = statistics.decode(data, (cores, current, previous, items, budget))
    elif chapter in (14, 15):
        decoded = workqueues.decode('R' if chapter == 14 else 'A', data,
            (slots, cores, items, items, items, items, budget, budget))
    else:
        decoded = outputs.decode(data, (items, budget)) # Chapter 16 has one ordered output sequence.
    head = decoded.split()[0]
    if not head.isdecimal():
        return head if head in {'truncated', 'noncanonical', 'limitexceeded', 'lengthoverflow', 'backendfailure'} else 'invalidcomponent'
    return 'ok' if int(head) == len(data) else 'trailingbytes'


# Transport contains values, not native-encoded expected payloads; metadata has a separately delimited fixed schema.
def service_token(service):
    sid, metadata, storage, preimages, requests, opaque = service
    return '|'.join([str(sid), metadata.hex(),
        ','.join(token(k)+':'+token(v) for k, v in storage) or '-',
        ','.join(h.hex()+':'+token(v) for h, v in preimages) or '-',
        ','.join(h.hex()+':'+str(n)+':'+history_wire(t).hex() for h, n, t in requests) or '-',
        ','.join(k.hex()+':'+token(v) for k, v in opaque) or '-'])


# Build mathematical mapping entries in the documented traversal order, without dict overwrite semantics.
def entries(values, services):
    result = [(chapter_key(i+1), value) for i, value in enumerate(values)]
    # Each service contributes metadata even if every nested map is empty.
    for sid, metadata, storage, preimages, requests, opaque in services:
        result.append((chapter_service(255, sid), metadata))
        result.extend((service_key('S', sid, k), v) for k, v in storage)
        result.extend((service_key('P', sid, h), v) for h, v in preimages)
        result.extend((request_key(sid, h, n), history_wire(t)) for h, n, t in requests)
        result.extend(opaque)
    return result


# Independent parent limits apply before key uniqueness/topology; original traversal order is observed too.
def composed(values, services, limits, key_limit):
    if any(len(k) > key_limit for _, _, storage, _, _, _ in services for k, _ in storage):
        return 'limitexceeded'
    pairs = entries(values, services)
    verdict = reference(pairs, limits)
    if verdict=='limitexceeded':
        return verdict # Complete parent capacity is checked before component encoding.
    if any(length>=2**32-2 for _,_,_,_,requests,_ in services for _,length,_ in requests):
        return 'invalidcomponent' # Current request encoders reject the two reserved namespace prefixes.
    if verdict=='duplicatekey':
        return verdict # A duplicate valid component has no partial mapping or root.
    return verdict+' '+''.join(k.hex()+':'+v.hex()+';' for k, v in pairs)


# Deterministic exact captures and complete typed compositions, with honest published-component verdicts.
def requests():
    values = chapters()
    assert all(capture(i+1, data) == 'ok' for i, data in enumerate(values))
    lines = ['B '+' '.join(map(str, PROFILE))+' '+' '.join(token(v) for v in values)]
    expected = ['selftest']
    evidence = []
    # Capture includes each exact component, every proper truncation, suffixes, mutations and strict policies.
    def cap(chapter, data, profile=PROFILE, policy=POLICY):
        lines.append('C '+' '.join(map(str, (*profile, *policy, chapter)))+' '+token(data))
        expected.append(capture(chapter, data, profile, policy))
    # Every complete chapter gets both proper-extent and malformed input evidence.
    for chapter, data in enumerate(values, 1):
        cap(chapter, data)
        cap(chapter, data+b'\0')
        cap(chapter, data, policy=(POLICY[0], len(data)-1))
        cap(chapter, data, policy=(0, POLICY[1]))
        for cut in range(len(data)):
            cap(chapter, data[:cut])
    # GP previous-rotation credentials retain their selected-roster indices after shrinkage.
    # Literal index7/8 and exclusive9 anchors are structural cases, not valid signature claims.
    guarantee = availability.record(0)
    guarantee['credentials'] = [(7, bytes(64)), (8, bytes(64))]
    retained = availability.wire([dict(guarantee=guarantee, registered=24), None, None])
    for profile, answer in (((3, 6, 9, 12), 'ok'), ((3, 9, 6, 12), 'ok'),
                            ((3, 6, 6, 12), 'invalidcomponent')):
        assert capture(10, retained, profile) == answer
        cap(10, retained, profile)
    guarantee['credentials'] = [(7, bytes(64)), (9, bytes(64))]
    beyond = availability.wire([dict(guarantee=guarantee, registered=24), None, None])
    for profile in ((3, 6, 9, 12), (3, 9, 6, 12)):
        assert capture(10, beyond, profile) == 'invalidcomponent'
        cap(10, beyond, profile)
    # The accepted compact gas profile has no E8 fallback at the exact-entry boundary.
    from state_widths_oracle import statistics_wire
    gas_source=([bytes(144),bytes(144)],[[0]*7+[100000],[0]*8],
        [(127,[0,0,0,128,0,0,0,0,0,0,256])])
    cap(13,statistics_wire(gas_source,4,0))
    assert capture(13,statistics_wire(gas_source,4,8))!='ok'
    cap(13,statistics_wire(gas_source,4,8))
    rng = random.Random(0x434f4d504f5345)
    # Arbitrary raw bytes exercise failures after compilation independently of child codec round trips.
    for _ in range(160):
        cap(rng.randrange(1, 17), rng.randbytes(rng.randrange(256)))
    for profile in ((1, 6, 6, 2), (2, 5, 6, 2), (2, 6, 9, 2), (2, 6, 6, 0)):
        cap(6, b'', profile)
    # Already pinned raw trace entries retain original bytes and explicit verdicts under the tiny epoch-12 profile.
    for pairs, provenance in published():
        by_key = dict(pairs)
        for chapter in range(1, 17):
            data = by_key[chapter_key(chapter)]
            verdict = capture(chapter, data, (2, 6, 6, 12))
            cap(chapter, data, (2, 6, 6, 12))
            evidence.append(dict(path=provenance['path'], phase=provenance['phase'], chapter=chapter,
                bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), verdict=verdict))
    # Complete compositions observe every key and value in addition to exact roots/counts.
    def add(services, limits=(MAX, MAX, MAX, MAX), key_limit=MAX, replacement=None):
        modified = values.copy()
        chapter, raw = replacement or (0, b'')
        if chapter:
            assert capture(chapter, raw) == 'ok'
            modified[chapter-1] = raw
        lines.append('S '+' '.join(map(str, (*limits, key_limit, chapter)))+' '+token(raw)+
            ''.join(' '+service_token(service) for service in services))
        expected.append(composed(modified, services, limits, key_limit))
    h = bytes(range(32))
    base = (7, bytes(105), [(b'', b''), (b'key', b'value')], [(h, b'preimage')],
        [(h, 8, (1,)), (h, 9, (1, 2, 3))], [])
    add([])
    add([base])
    pairs = entries(values, [base])
    _, nodes = tree(pairs)
    tight = (len(pairs), max(len(v) for _, v in pairs), sum(len(v) for _, v in pairs), nodes)
    add([base], tight, 3)
    # Each parent budget is independently binding on this complete mapping.
    for field in range(4):
        below = list(tight)
        below[field] -= 1
        add([base], tuple(below), 3)
    add([base], tight, 2)
    add([base, base])
    add([(7, bytes(105), [(b'x', b'a'), (b'x', b'b')], [], [], [])])
    add([(7, bytes(105), [], [(h, b'p')], [(h, 2**32-2, ())], [])])
    add([(7, bytes(105), [(h, b's')], [], [(h, 2**32-1, ())], [])])
    # Opaque values can replace known raw storage entries while preserving their exact key and service identity.
    opaque = service_key('S', 7, b'unknown original key')
    add([(7, bytes(105), [], [], [], [(opaque, b'opaque')])])
    # The current ambiguous widths are exercised explicitly without declaring normative conformance.
    add([], replacement=(12, privileges.wire((1, 4, 5, [2, 3], [(127, 128), (256, MAX)]))))
    add([], replacement=(13, statistics.wire(statistics.example())))
    # Fresh multi-service sources exercise empty/present values, wide identities, all history modes and permutations.
    for _ in range(50):
        services = []
        for sid in rng.sample(range(2**32), rng.randrange(1, 5)):
            content = rng.randbytes(rng.randrange(80))
            hashed = hashlib.blake2b(content, digest_size=32).digest()
            times = tuple(rng.getrandbits(32) for _ in range(rng.randrange(4)))
            metadata = b'\0'+rng.randbytes(104)
            services.append((sid, metadata, [(rng.randbytes(8), content)], [(hashed, content)],
                [(hashed, len(content), times)], []))
        add(services)
        add(services[::-1])
    whole_evidence = []
    # Only states whose sixteen complete chapter captures pass can enter this published composition check.
    for pairs, provenance in published():
        by_key = dict(pairs)
        raw_chapters = [by_key[chapter_key(i)] for i in range(1, 17)]
        if any(capture(i+1, data, (2, 6, 6, 12)) != 'ok' for i, data in enumerate(raw_chapters)):
            continue # Retain the original chapter failures above; never repair them to obtain a root.
        accounts = {}
        # Full C(255,service) identities identify metadata; a leading ff alone is never sufficient.
        for key, value in pairs:
            sid = int.from_bytes(key[1:8:2], 'little')
            if key == chapter_service(255, sid):
                assert len(value) == 89 and value[0] == 0
                # Derived current-schema composition; original release roots remain separately recorded.
                value = value[:33]+bytes(8)+value[33:41]+bytes(8)+value[41:]
                accounts[sid] = (sid, value, [], [], [], [])
        chapter_keys = {chapter_key(i) for i in range(1, 17)}
        metadata_keys = {chapter_service(255, sid) for sid in accounts}
        # Original storage keys/lookup identities are not reconstructed from digest bytes.
        for key, value in pairs:
            if key in chapter_keys or key in metadata_keys:
                continue # These identities have already received their exact typed chapter/metadata schema.
            sid = int.from_bytes(key[:8:2], 'little')
            assert sid in accounts, (provenance, 'opaque value without metadata service')
            accounts[sid][5].append((key, value))
        services = list(accounts.values())
        rebuilt = entries(raw_chapters, services)
        # Release inputs are converted explicitly: new metadata necessarily changes the derived root.
        derived_pairs = [(k, v[:33]+bytes(8)+v[33:41]+bytes(8)+v[41:] if len(v)==89 and k[0]==255 and k==chapter_service(255,int.from_bytes(k[1:8:2],'little')) else v) for k,v in pairs]
        assert sorted(rebuilt) == sorted(derived_pairs)
        lines.append('B 2 6 6 12 '+' '.join(token(v) for v in raw_chapters))
        expected.append('selftest')
        lines.append('S '+' '.join(map(str, (MAX, MAX, MAX, MAX, MAX, 0)))+' -'+
            ''.join(' '+service_token(service) for service in services))
        expected.append(composed(raw_chapters, services, (MAX,)*4, MAX))
        whole_evidence.append(dict(provenance, service_values='opaque service-bound captures',
            chapter_schema='migrated C12 E4/E8 and C13 E4 keys; compact statistics gas accepted by maintainer policy'))
    return lines, expected, evidence, whole_evidence
