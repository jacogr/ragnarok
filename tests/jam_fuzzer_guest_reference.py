# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Adapt independent full STF references into exact fuzzer inputs without consulting native output."""
import hashlib


def replay(reference):
    """Take only the reference's independently authored seed/child stream; retain every expected complete map."""
    _, expected, evidence = reference.expected_observations()
    requests, initialized, waiting, blocks = [], False, False, 0
    for line in expected:
        tag, data = line.split(' ', 1)
        if tag == 'P':
            assert not waiting and (not initialized or blocks > 0)
            blocks = 0
            requests.append('C '+data)
            initialized = True
        elif tag == 'B':
            assert initialized and not waiting
            requests.append(line)
            waiting = True
            blocks += 1
        else:
            assert tag == 'O' and waiting, 'Unsupported reference observation: '+tag
            waiting = False
    assert initialized and not waiting and blocks > 0
    return requests, expected, dict(reference=evidence,
        requests_sha256=hashlib.sha256(('\n'.join(requests)+'\n').encode()).hexdigest(),
        expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
