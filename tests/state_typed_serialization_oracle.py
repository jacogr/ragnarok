# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""GP-derived complete typed-source comparisons across independent chain cardinalities.

All chapter bytes and complete checkpoint commitments come from Python equations.
No native output or upstream format conversion supplies an expected byte.
"""
import hashlib
import json
from pathlib import Path
from state_composition_oracle import entries, capture
from state_complete_serialization_oracle import source, checkpoint
from test_codec import reference_encode as natural
import state_authorization_oracle as authorization
import state_history_oracle as history
import state_consensus_oracle as consensus
import state_disputes_oracle as disputes
import state_privileges_oracle as privileges
import state_statistics_oracle as statistics
import state_availability_oracle as availability
import state_workqueues_oracle as workqueues
import state_outputs_oracle as outputs

PROFILES = ((2, 6, 6, 12), (3, 9, 6, 12), (3, 6, 9, 12), (341, 1023, 1023, 600))
POLICY = (50000, 2000000)

def pattern(size, seed):
    """Distinct octets preserve positional evidence without implying cryptographic validity."""
    return bytes((seed+i) % 251 for i in range(size))

def report_wire(profile):
    """Author the C2 report equation directly, including fixed gas and all five natural load fields."""
    cores, current, _, _ = profile
    header = bytes(68)+current.to_bytes(2, 'little')+bytes(202)
    digest = ((2**32-1).to_bytes(4, 'little')+pattern(32, 73)+pattern(32, 107)
              +(2**64-1).to_bytes(8, 'little')+b'\0\0'
              +b''.join(natural(x) for x in (128, 127, 256, 2**32, 16384)))
    return (header+natural(0)+natural(cores-1)+pattern(32, 7)+natural(128)
            +natural(0)+natural(0)+natural(1)+digest)

def chapters(profile, kind):
    """Populate every chapter, retaining fixed rings, ordered tuples and canonical sets."""
    cores, current, previous, slots = profile
    roster = lambda count, seed: natural(count)+pattern(336*count, seed)
    hashes = bytes([1])*32+bytes([2])*32
    pending = pattern(336*current, 11)
    schedule = pattern(slots*(33 if kind == 0 else 32), 23)
    report = report_wire(profile)
    guarantee = dict(report=report, slot=2**32-1,
                     credentials=[(i, bytes([17+i])*64) for i in range(2)])
    ready = [[(report, hashes)]]+[[] for _ in range(slots-1)]
    accumulated = [hashes]+[b'' for _ in range(slots-1)]
    return [
        authorization.wire(0, [pattern(32*(i % 3+1), i) for i in range(cores)]),
        authorization.wire(1, [pattern(80*32, i+7) for i in range(cores)]),
        history.wire(([(pattern(96, 17)+(2**32-1).to_bytes(4, 'little'),
                        bytes([1])*32+bytes([7])*32)], [None, bytes(32), pattern(32, 31)])),
        consensus.wire((pending, pattern(144, 37), kind, schedule, pattern(33, 43))),
        disputes.wire([hashes, bytes([3])*32, bytes([4])*32, bytes([5])*32]),
        pattern(128, 47), roster(6, 53), roster(current, 59), roster(previous, 61),
        availability.wire([None for _ in range(cores-1)]+[dict(guarantee=guarantee, registered=2**32-1)]),
        (2**32-1).to_bytes(4, 'little'),
        privileges.wire((2**32-1, 256, 0, [i+1 for i in range(cores)],
                         [(1, 2**64-1), (256, 128), (2**32-1, 0)])),
        statistics.wire(([(i, 1, 127, 128, 65536, 2**32-1) for i in range(current)],
                         [(i, 2, 255, 256, 16384, 2**32-1) for i in range(previous)],
                         [(0, 127, 128, 255, 256, 16384, 2**32, 2**64-1)]*cores,
                         [(1, *range(11)), (256, *([2**64-1]*11))])),
        workqueues.wire('R', ready), workqueues.wire('A', accumulated),
        outputs.wire([(2**32-1, pattern(32, 67)), (0, bytes(32)), (2**32-1, pattern(32, 71))])]

def cases():
    """Keep profile, schedule alternative, logical service and exact expected bytes bound together."""
    for profile_index, profile in enumerate(PROFILES):
        for kind in range(2):
            case_id = 2*profile_index+kind
            values = chapters(profile, kind)
            service = source(case_id)[1]
            yield profile, kind, case_id, values, checkpoint(entries(values, [service]))

def encoded():
    """Generate trusted transport with independent precise truncated-child failure expectations."""
    lines = []
    for profile, kind, case_id, values, expected in cases():
        assert all(capture(i+1, value, profile, POLICY) == 'ok' for i, value in enumerate(values))
        reasons = [capture(i+1, value[:-1], profile, POLICY) for i, value in enumerate(values)]
        assert all(reason != 'ok' for reason in reasons)
        lines.append(' '.join(map(str, (*profile, kind, case_id)))+' '+
                     ' '.join(value.hex() for value in values)+' '+expected.hex()+' '+','.join(reasons))
    return ('\n'.join(lines)+'\n').encode()

def prepare(folder):
    """Write only ignored generated inputs, retaining exact input identity for the native runner."""
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'state-typed-serialization.txt'
    raw = encoded()
    anchors = json.loads((Path(__file__).parent/'fixtures/typed-serialization-anchors.json').read_text())
    assert hashlib.sha256(raw).hexdigest() == anchors['fixture_sha256']
    path.write_bytes(raw)
    return path, dict(fixture_sha256=hashlib.sha256(raw).hexdigest(), cases=8,
                      authority='pinned GP-derived equations; no external implementation output')
