# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map continuation witnesses selected from five lifecycle equation families."""
import hashlib
import importlib
import json
from pathlib import Path
import current_stf_transfers_oracle as transfers

FIXTURE = Path(__file__).parent/'fixtures/current-stf-checkpoint-replay.json'
CASES = (('service_upgrades', 0, 47), ('request_lifecycle', 2, 64),
         ('preimage_provision', 2, 69), ('service_creation', 3, 60), ('supervisor_lifecycle', 0, 52))


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
    for family, ordinal, mode in CASES:
        source = importlib.import_module('current_stf_'+family+'_oracle')
        incoming, expected, evidence = source.expected_observations()
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
