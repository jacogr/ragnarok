# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent funded creation, retirement, recreation and queued-incarnation fuzz siblings."""
from pathlib import Path
from jam_fuzzer_effect_forks_reference import group

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-account-forks.json'
FAMILIES = ('reserved_creation', 'child_readiness', 'child_retirement', 'child_recreation', 'incarnation_authority', 'foreign_creation', 'foreign_transfers', 'queued_incarnation')


def expected_observations(check_frozen=True):
    """Calculate complete account lifecycle siblings and original-last continuation before native execution."""
    return group(FAMILIES, FIXTURE, check_frozen=check_frozen)
