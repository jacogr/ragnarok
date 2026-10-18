# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent set/sequence projection of GP E/Q; never simulates accumulation execution.

Exposes priority for test-only mathematical expectations and prepare for pinned-input plus
seeded-graph fixture transport. Report codecs and upstream SHA-256 checks remain independent.
"""
import hashlib
import json
import random
from state_workqueues_oracle import blob, wire
from report_oracle import from_json, encode


# Integer-sized set operations and recursive waves are independent of native sorted indices/edit buffers.
def priority(available, ready, history, slot):
    immediate = [r for r in available if not r['prerequisites'] and not r['lookup']]
    past = set().union(*history)
    deferred = [(r, set(r['prerequisites']) | set(r['lookup'])) for r in available
                if r['prerequisites'] or r['lookup']]

    # E retains report order and removes whole packages as well as satisfied dependencies.
    def edit(rows, hashes):
        return [(r, deps-hashes) for r, deps in rows if r['key'] not in hashes]

    # Q emits the whole current ready wave before recursively considering newly unlocked work.
    def queue(rows):
        wave = [r for r, deps in rows if not deps]
        if not wave:
            return []
        return wave + queue(edit(rows, {r['key'] for r in wave}))

    start = slot % len(ready)
    pending = [item for row in ready[start:]+ready[:start] for item in row]
    pending += edit(deferred, past)
    pending = edit(pending, {r['key'] for r in immediate})
    return immediate + queue(pending), pending, len(immediate)


# Preserve full report bytes; dependency identities are extracted separately for the mathematical oracle.
def report(item):
    value = from_json(item)
    return dict(layout=value, key=value['header'][:32], wire=encode(value),
                prerequisites={bytes.fromhex(v[2:]) for v in item['context']['prerequisites']},
                lookup={bytes.fromhex(v['work_package_hash'][2:]) for v in item['segment_root_lookup']})


# Serialize only trusted fixture transport, with explicit expected report bytes and edited dependency sets.
def row(name, cores, available, ready, history, slot):
    selected, pending, immediate = priority(available, ready, history, slot)
    ready_wire = wire('Q', [[(r['wire'], b''.join(sorted(deps))) for r, deps in bucket] for bucket in ready])
    history_wire = wire('A', [b''.join(sorted(bucket)) for bucket in history])
    token = lambda values: ','.join(values) or '-'
    return ' '.join((name, str(cores), str(len(ready)), str(slot), ready_wire.hex(), history_wire.hex(),
                     token(r['wire'].hex() for r in available), str(immediate),
                     token(r['wire'].hex() for r in selected),
                     token(r['key'].hex()+':'+(b''.join(sorted(deps)).hex() or '-') for r, deps in pending)))


# Published inputs retain their pinned identities; random graphs are explicitly authored property checks.
def prepare(folder):
    rows, sources = [], []
    template = None
    for chain, cores in (('tiny', 2), ('full', 341)):
        for name in ('accumulate_ready_queued_reports-1', 'enqueue_and_unlock_chain-1',
                     'enqueue_and_unlock_chain_wraps-1'):
            path = f'stf/accumulate/{chain}/{name}.json'
            case = blob(path)
            before = case['pre_state']
            ready = [[(report(x['report']), {bytes.fromhex(d[2:]) for d in x['dependencies']})
                      for x in bucket] for bucket in before['ready_queue']]
            history = [{bytes.fromhex(x[2:]) for x in bucket} for bucket in before['accumulated']]
            available = [report(r) for r in case['input']['reports']]
            selected, _, _ = priority(available, ready, history, case['input']['slot'])
            # These six cases execute every selected report: upstream posterior history independently checks membership.
            post = {bytes.fromhex(x[2:]) for bucket in case['post_state']['accumulated'] for x in bucket}
            assert {r['key'] for r in selected} == post-set().union(*history), path
            rows.append(row(path, cores, available, ready, history, case['input']['slot']))
            sources.append(path)
            if chain == 'tiny':
                # Only the full original report bytes are reused as payload templates in authored graphs.
                template = next((r for bucket in ready for r, _ in bucket), None) or available[0]
    rng = random.Random(0x455151)
    for case in range(256):
        ready = [[] for _ in range(12)]
        history = [set() for _ in range(12)]
        available = []
        for index in range(12):
            key = bytes([index+1])+bytes(31)
            deps = {bytes([rng.randrange(1, 15)])+bytes(31) for _ in range(rng.randrange(4))}
            # Report-wire fields remain valid, but graph dependencies may deliberately be cyclic or unavailable.
            value = dict(key=key, wire=key+template['wire'][32:], prerequisites=set(), lookup=set())
            ready[rng.randrange(12)].append((value, deps))
            if rng.randrange(4) == 0:
                history[rng.randrange(12)].add(key)
        for index in range(rng.randrange(7)):
            key = bytes([index+13])+bytes(31)
            prerequisites = {bytes([rng.randrange(1, 21)])+bytes(31) for _ in range(rng.randrange(4))}
            lookups = {bytes([rng.randrange(1, 21)])+bytes(31) for _ in range(rng.randrange(3))}
            layout = dict(template['layout'], header=key+template['layout']['header'][32:],
                          prerequisites=b''.join(sorted(prerequisites)),
                          lookup=b''.join(d+bytes(32) for d in sorted(lookups)))
            available.append(dict(key=key, wire=encode(layout), prerequisites=prerequisites, lookup=lookups))
            if rng.randrange(4) == 0:
                # Deliberately exercise whole deferred-report removal, while immediate records keep their literal rule.
                history[rng.randrange(12)].add(key)
        rows.append(row(f'authored-{case}', 2, available, ready, history, rng.randrange(2**32)))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'accumulation-queue.txt'
    path.write_text('\n'.join(rows)+'\n')
    evidence = dict(published=6, authored=256, sources=sources,
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'accumulation-queue.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
