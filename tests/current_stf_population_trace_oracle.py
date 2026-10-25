# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independently authored complete TraceSteps drive authenticated changing-roster imports; expected maps are comparison-only."""
from pathlib import Path
from reporting_scenario_oracle import collect,validate_frozen
from reporting_replay_oracle import cases,origins,SOURCES as BASES
from current_stf_population_restart_oracle import FIXTURE as RESTART
from state_trace_wire_oracle import wire as raw_state

FIXTURE=Path(__file__).parent/'fixtures/current-stf-population-trace.json'
SOURCES=(*BASES,RESTART)
CONTROLS=('R PreStateMismatch','R PostStateMismatch','R CandidateFailure')


def expected_observations(check_frozen=True):
    """Calculate all exact pre/block/post wires before native execution; original refusals preserve the same selected parent."""
    chains=cases();requests,expected,evidence=collect(chains,FIXTURE,SOURCES,False)
    traces=[]
    for case in chains:
        parent=case['initial']
        for block,after,_ in case['steps']:
            traces.append(raw_state(list(parent.items()))+block+raw_state(list(after.items())))
            parent=after # Only independently calculated mathematical successors supply expected maps.
    encoded=iter(traces)
    inputs=['T '+next(encoded).hex() if line.startswith('B ') else line for line in requests]
    assert next(encoded,None) is None
    lines=[]
    for line in expected:
        lines.append(line)
        if line.startswith('B '):lines.extend(CONTROLS)
    evidence.update(trace_refusals=3*evidence['transitions'],origins=[list(item) for item in origins()])
    if check_frozen:validate_frozen(FIXTURE,SOURCES,evidence)
    return inputs,lines,evidence
