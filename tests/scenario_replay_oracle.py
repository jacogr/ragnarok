# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Adapt independent histories to restart and full-trace inputs, retaining frozen evidence and refusal controls."""
from reporting_scenario_oracle import collect, validate_frozen
from state_trace_wire_oracle import wire as raw_state


def _finish(suite, fixture, sources, check_frozen, requests, expected, evidence, marker, controls):
    """Insert the exact adapter controls and bind source-owned provenance before returning observations."""
    lines = []
    for line in expected:
        lines.append(line)
        if line.startswith(marker):
            # Refusals stay immediately after their original transition observation.
            lines.extend(controls)
    evidence['origins'] = suite.origins()
    if check_frozen:
        # Each adapter's own fixture and source pins remain authoritative.
        validate_frozen(fixture, sources, evidence)
    return requests, lines, evidence


def restart_observations(suite, fixture, sources, check_frozen=True):
    """Bind every block to its independently calculated successor root and require checkpoint refusal/restoration."""
    chains = suite.cases()
    requests, expected, evidence = collect(chains, fixture, sources, False)
    roots = iter(root for row in evidence['roots'] for root in row)
    requests = ['S '+line[2:]+' '+next(roots) if line.startswith('B ') else line for line in requests]
    assert next(roots, None) is None
    evidence.update(restarts=evidence['transitions'], checkpoint_refusals=2*evidence['transitions'])
    return _finish(suite, fixture, sources, check_frozen, requests, expected, evidence, 'O ',
                   ('K RootMismatch', 'K LimitExceeded', 'K Restored'))


def trace_observations(suite, fixture, sources, check_frozen=True):
    """Frame each original parent, signed block and successor as a complete independently authored trace."""
    chains = suite.cases()
    requests, expected, evidence = collect(chains, fixture, sources, False)
    wires = []
    for case in chains:
        parent = case['initial']
        for block, state, _ in case['steps']:
            # Advance only along this case's authored successors; native observations never enter the wire.
            wires.append(raw_state(list(parent.items()))+block+raw_state(list(state.items())))
            parent = state
    source = iter(wires)
    requests = ['T '+next(source).hex() if line.startswith('B ') else line for line in requests]
    assert next(source, None) is None
    evidence.update(trace_refusals=3*evidence['transitions'])
    return _finish(suite, fixture, sources, check_frozen, requests, expected, evidence, 'B ',
                   ('R PreStateMismatch', 'R PostStateMismatch', 'R CandidateFailure'))
