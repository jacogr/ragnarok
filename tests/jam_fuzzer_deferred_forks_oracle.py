# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map deferred effect-bearing fuzz siblings and original-last continuation."""
from pathlib import Path
from jam_fuzzer_effect_forks_reference import group

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-deferred-forks.json'
FAMILIES = ('dependency_waves', 'budget_retention', 'gas_exits', 'late_code')


def expected_observations(check_frozen=True):
    """Calculate genuine siblings and exact complete original-last maps before native execution."""
    return group(FAMILIES, FIXTURE, check_frozen=check_frozen)
