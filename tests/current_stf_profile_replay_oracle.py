# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map current-profile checkpoint continuation across supervision, privileges and complete service lifecycles."""
import hashlib
import importlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers

FIXTURE = Path(__file__).parent/'fixtures/current-stf-profile-replay.json'
CASES = (('supervised_storage',0,82),('supervised_storage',3,85),
         ('supervised_requests',2,89),('supervised_conflicts',0,97),('supervised_handoff',0,102),
         ('authorization_assign',0,107),('authorization_assign',5,112),('role_precedence',0,113),
         ('validator_designation',0,118),('reserved_creation',1,124),('reserved_creation',7,130),
         ('child_readiness',0,131),('child_readiness',2,133),('preimage_aging',1,137),
         ('child_retirement',1,142),('child_retirement',5,146),
         ('child_recreation',1,149),('child_recreation',5,153))


def groups(lines, prefix):
    """Partition only explicit profile boundaries, preserving each full original and exact ordered successor stream."""
    result = []
    for line in lines:
        if line.startswith(prefix):
            result.append([]) # A new complete original starts a separate independently derived chain.
        result[-1].append(line)
    return result


def expected_observations(check_frozen=True):
    """Reuse mathematical successors byte-for-byte while requiring a new decoded state owner after every child."""
    requests, lines, roots, hashes, traces = [], [], [], [], []
    cache = {}
    for family, ordinal, mode in CASES:
        source = importlib.import_module('current_stf_'+family+'_oracle')
        if family not in cache:
            cache[family] = source.expected_observations() # Derive each entire equation family once, with its own frozen contract checked.
        incoming, expected, evidence = cache[family]
        selected = groups(incoming, 'C ')[ordinal]
        assert selected[0] == 'C '+str(mode)
        requests.extend([selected[0]+' reload', *selected[1:]])
        lines.extend(groups(expected, 'P ')[ordinal])
        roots.append(evidence['roots'][ordinal]); hashes.append(evidence['checkpoint_sha256'][ordinal])
        traces.append(dict(family=family, mode=mode, transitions=len(selected)-1,
                           fixture_sha256=hashlib.sha256(source.FIXTURE.read_bytes()).hexdigest()))
    if check_frozen:
        fixture = json.loads(FIXTURE.read_text())
        assert fixture['graypaper_commit'] == '1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d'
        assert fixture['base_fixture_sha256'] == hashlib.sha256(transfers.FIXTURE.read_bytes()).hexdigest()
        assert fixture['successor_roots'] == roots and fixture['successor_checkpoint_sha256'] == hashes
        assert fixture['traces'] == traces
    return requests, lines, dict(transitions=sum(len(row) for row in roots), chains=len(CASES),
                                roots=roots, checkpoint_sha256=hashes, traces=traces)
