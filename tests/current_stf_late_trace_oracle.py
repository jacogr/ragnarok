# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete late-code history trace qualification retains selected state on exact typed refusals."""
from pathlib import Path
import late_replay_oracle as suite
from scenario_replay_oracle import trace_observations

FIXTURE=Path(__file__).parent/'fixtures/current-stf-late-trace.json'
import current_stf_late_restart_oracle as restart
SOURCES=(*suite.SOURCES,restart.FIXTURE)
NATIVE_DEFINES=suite.NATIVE_DEFINES


def expected_observations(check_frozen=True):
    """Author all authenticated wires and expected roots before the native chain sees any input."""
    return trace_observations(suite, FIXTURE, SOURCES, check_frozen)
