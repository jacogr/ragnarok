# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Adapt independent full STF references into exact fuzzer inputs without consulting native output."""
import hashlib


def host_parameters(*, code_limit=512, lookup_age=2**32-1, deposits=(0, 0, 0)):
    """Author explicit host configuration from the established independent Tiny tuple, never from a supplied state root."""
    from current_stf_trace_command_oracle import parameters
    assert 0 <= code_limit < 2**32 and 0 <= lookup_age < 2**32
    assert len(deposits) == 3 and all(0 <= value < 2**64 for value in deposits)
    wire = bytearray(parameters(0))
    wire[98:102] = code_limit.to_bytes(4, 'little')
    wire[74:78] = lookup_age.to_bytes(4, 'little')
    wire[:24] = b''.join(value.to_bytes(8, 'little') for value in deposits)
    return bytes(wire)


def replay(reference, *, input_requests=True, profiles=None, forks=False, anchor_checks=False, headers=False):
    """Take only the reference's independently authored seed/child stream; retain every expected complete map."""
    if input_requests:
        _, expected, evidence = reference.expected_observations()
    else:
        expected, evidence = reference.expected_observations() # This reference explicitly returns only the full observation stream.
    if profiles is not None:
        assert len(profiles) == sum(line.startswith('P ') for line in expected)
        assert all(isinstance(profile, bytes) and len(profile) == 122 for profile in profiles)
    ordinal = 0
    requests, initialized, waiting, blocks = [], False, False, 0
    sibling = False
    header_pending = False
    for line in expected:
        tag, data = line.split(' ', 1)
        if tag == 'H':
            assert headers and not waiting and not sibling and not header_pending
            header_pending = True
            requests.append(line) # Explicit independent seed headers are never reconstructed from observed state.
        elif tag == 'P':
            assert not waiting and not sibling and (not initialized or blocks > 0)
            header_pending = False
            blocks = 0
            profile = '' if profiles is None else ' '+profiles[ordinal].hex()
            requests.append(('A ' if anchor_checks else 'C ')+data+profile)
            ordinal += 1
            initialized = True
        elif tag == 'B' or forks and tag == 'V':
            assert initialized and not waiting and not header_pending
            if tag == 'V':
                sibling = True # Consecutive depth-one variants still require an eventual original-last child.
            else:
                sibling = False
            requests.append(line)
            waiting = True
            blocks += 1
        else:
            assert tag == 'O' and waiting, 'Unsupported reference observation: '+tag
            waiting = False
    assert initialized and not waiting and not sibling and not header_pending and blocks > 0
    return requests, expected, dict(reference=evidence,
        requests_sha256=hashlib.sha256(('\n'.join(requests)+'\n').encode()).hexdigest(),
        expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
