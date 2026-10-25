# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete host-history restart qualification retains selected state on exact typed refusals."""
from pathlib import Path
import rotation_replay_oracle as suite
from reporting_scenario_oracle import collect,validate_frozen
from state_trace_wire_oracle import wire as raw_state

FIXTURE=Path(__file__).parent/'fixtures/current-stf-rotation-restart.json'
SOURCES=suite.SOURCES
NATIVE_DEFINES=suite.NATIVE_DEFINES


def expected_observations(check_frozen=True):
    """Author all authenticated wires and expected roots before the native chain sees any input."""
    chains=suite.cases();requests,expected,evidence=collect(chains,FIXTURE,SOURCES,False)
    roots=iter(root for row in evidence['roots'] for root in row)
    requests=['S '+line[2:]+' '+next(roots) if line.startswith('B ') else line for line in requests]
    assert next(roots,None) is None
    controls=('K RootMismatch','K LimitExceeded','K Restored');marker='O '
    evidence.update(restarts=evidence['transitions'],checkpoint_refusals=2*evidence['transitions'])
    lines=[]
    for line in expected:
        lines.append(line)
        if line.startswith(marker):lines.extend(controls)
    evidence['origins']=suite.origins()
    if check_frozen:validate_frozen(FIXTURE,SOURCES,evidence)
    return requests,lines,evidence
