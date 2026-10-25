# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent whole-map transfer siblings across direct/foreign/forwarded delivery and funding/admission/memos."""
from pathlib import Path
from jam_fuzzer_effect_forks_reference import group

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-transfer-forks.json'
FAMILIES = ('transfers', 'supervised_transfers', 'forwarded_transfers', 'transfer_pools', 'transfer_admission', 'transfer_memos')


def expected_observations(check_frozen=True):
    """Calculate each transfer-bearing sibling and every original-last continuation before native execution."""
    return group(FAMILIES, FIXTURE, check_frozen=check_frozen)
