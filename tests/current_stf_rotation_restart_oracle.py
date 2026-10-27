# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete host-history restart qualification retains selected state on exact typed refusals."""
from pathlib import Path
import rotation_replay_oracle as suite
from scenario_replay_oracle import restart_observations

FIXTURE=Path(__file__).parent/'fixtures/current-stf-rotation-restart.json'
SOURCES=suite.SOURCES
NATIVE_DEFINES=suite.NATIVE_DEFINES


def expected_observations(check_frozen=True):
    """Author all authenticated wires and expected roots before the native chain sees any input."""
    return restart_observations(suite, FIXTURE, SOURCES, check_frozen)
