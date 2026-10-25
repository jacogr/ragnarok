# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent full-checkpoint continuation supplies only expected roots, never expected posterior maps for construction."""
from pathlib import Path
from reporting_scenario_oracle import collect,validate_frozen
from reporting_replay_oracle import cases,SOURCES,origins

FIXTURE=Path(__file__).parent/'fixtures/current-stf-population-restart.json'
CONTROLS=('K RootMismatch','K LimitExceeded','K Restored')


def expected_observations(check_frozen=True):
    """Bind each genuine block to an independently calculated posterior root and require exact restart/refusal observations."""
    requests,expected,evidence=collect(cases(),FIXTURE,SOURCES,False)
    roots=iter(root for chain in evidence['roots'] for root in chain)
    inputs=['S '+line[2:]+' '+next(roots) if line.startswith('B ') else line for line in requests]
    assert next(roots,None) is None
    lines=[]
    for line in expected:
        lines.append(line)
        if line.startswith('O '):lines.extend(CONTROLS)
    evidence.update(restarts=evidence['transitions'],checkpoint_refusals=2*evidence['transitions'],origins=origins())
    # JSON uses arrays for explicit ordered origin tuples; retain one canonical frozen representation.
    evidence['origins']=[list(item) for item in evidence['origins']]
    if check_frozen:validate_frozen(FIXTURE,SOURCES,evidence)
    return inputs,lines,evidence
