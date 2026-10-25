# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map supervised effect-bearing fuzz siblings and original-last continuation."""
from pathlib import Path
from jam_fuzzer_effect_forks_reference import group

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-supervised-forks.json'
FAMILIES = ('supervised_storage', 'supervised_requests', 'supervised_upgrades', 'supervised_conflicts', 'supervised_handoff')


def expected_observations(check_frozen=True):
    """Calculate genuine siblings and exact complete original-last maps before native execution."""
    return group(FAMILIES, FIXTURE, check_frozen=check_frozen)
