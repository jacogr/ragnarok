# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete host-history trace qualification retains selected state on exact typed refusals."""
from pathlib import Path
import rotation_replay_oracle as suite
from reporting_scenario_oracle import collect,validate_frozen
from state_trace_wire_oracle import wire as raw_state

FIXTURE=Path(__file__).parent/'fixtures/current-stf-rotation-trace.json'
SOURCES=suite.SOURCES
NATIVE_DEFINES=suite.NATIVE_DEFINES


def expected_observations(check_frozen=True):
    """Author all authenticated wires and expected roots before the native chain sees any input."""
    chains=suite.cases();requests,expected,evidence=collect(chains,FIXTURE,SOURCES,False)
    wires=[]
    for case in chains:
        parent=case['initial']
        for block,state,_ in case['steps']:
            wires.append(raw_state(list(parent.items()))+block+raw_state(list(state.items())))
            parent=state
    source=iter(wires)
    requests=['T '+next(source).hex() if line.startswith('B ') else line for line in requests]
    assert next(source,None) is None
    controls=('R PreStateMismatch','R PostStateMismatch','R CandidateFailure');marker='B '
    evidence.update(trace_refusals=3*evidence['transitions'])
    lines=[]
    for line in expected:
        lines.append(line)
        if line.startswith(marker):lines.extend(controls)
    evidence['origins']=suite.origins()
    if check_frozen:validate_frozen(FIXTURE,SOURCES,evidence)
    return requests,lines,evidence
