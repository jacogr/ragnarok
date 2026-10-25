# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent shared whole-map scaffolding for literal host effects across changing validator counts."""
from state_layout_oracle import chapter_key, chapter_service
from state_accounts_oracle import parse as account_parse, wire as account_wire
from state_statistics_oracle import parse as statistics_parse, wire as statistics_wire, DEFAULT
import current_stf_population_guests_oracle as execution
from current_stf_population_anchors_oracle import parameters as base_parameters


def parameters():
    """Author the complete three-core tuple with an explicit4096-byte service-code maximum."""
    wire = bytearray(base_parameters())
    wire[98:102] = (4096).to_bytes(4, 'little')
    return bytes(wire)


def original(services, privileges):
    """Combine independent dynamic globals and authored service namespaces before signing any block."""
    globals_ = execution.population.original()
    result = {k: v for k, v in globals_.items() if k in {chapter_key(i) for i in range(1, 17)}}
    result.update({k: v for k, v in services.items() if k not in {chapter_key(i) for i in range(1, 17)}})
    result[chapter_key(12)] = privileges
    return result


def statistics_config(state):
    """Read exact current/previous dimensions from independently calculated posterior roster membership."""
    current = len(execution.epoch.roster(state[chapter_key(8)]))
    previous = len(execution.epoch.roster(state[chapter_key(9)]))
    return (3, current, previous, *DEFAULT[3:])


def statistics(state):
    """Read service activity without changing the actual current/previous/core statistics."""
    return statistics_parse(state[chapter_key(13)], statistics_config(state))[0]


def charge(state, sid, slot, gas, operands=0, transfers=0):
    """Stamp genuine invocation participation and add explicit service gas without replacing validator/core statistics."""
    key = chapter_service(255, sid)
    code, wide, narrow = account_parse(state[key], 105)
    narrow = list(narrow); narrow[2] = slot
    state[key] = account_wire((code, wide, narrow))
    current, previous, cores, services = statistics(state)
    activity = {row[0]: list(row) for row in services}
    row = activity.setdefault(sid, [sid]+[0]*11)
    row[9] += operands; row[10] += transfers; row[11] += gas
    state[chapter_key(13)] = statistics_wire((current, previous, cores, [tuple(activity[s]) for s in sorted(activity)]))


def advance(parent, slot, guaranteed, assured, reports, *, queues=None, foundation=None):
    """Use mathematical signatures/admission/rotation with host effects supplied separately from report processing."""
    return execution.advance(parent, 'create', slot, guaranteed, assured, reports,
        batches=[], yielded=False, authorization_queues=queues, foundation_override=foundation)


def privileges(data, cores=3):
    """Decode the independently fixed E4 roles and canonical compact-count E4/E8 allowance pairs."""
    from test_codec import reference_decode
    roles = [int.from_bytes(data[i:i+4], 'little') for i in range(0, 4*(cores+3), 4)]
    count, width = map(int, reference_decode(data[4*(cores+3):]).split())
    start = 4*(cores+3)+width
    assert len(data) == start+12*count
    pairs = [(int.from_bytes(data[i:i+4], 'little'), int.from_bytes(data[i+4:i+12], 'little'))
             for i in range(start, len(data), 12)]
    return roles[0], roles[-2], roles[-1], roles[1:cores+1], pairs
