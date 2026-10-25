# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete-map epoch effect-bearing fuzz siblings and original-last continuation."""
from pathlib import Path
from jam_fuzzer_effect_forks_reference import group

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-epoch-effect-forks.json'
FAMILIES = ('epoch_drain', 'ready_expiry', 'epoch_lifecycle', 'epoch_composition')


def expected_observations(check_frozen=True):
    """Calculate genuine siblings and exact complete original-last maps before native execution."""
    return group(FAMILIES, FIXTURE, check_frozen=check_frozen)


def host_profiles():
    """Declare exact source profiles, including the mixed independently authored epoch-composition cases."""
    import importlib
    import json
    from jam_fuzzer_effect_forks_reference import profiles
    result = profiles(FAMILIES[:-1])
    source = importlib.import_module('current_stf_epoch_composition_oracle')
    frozen = json.loads(source.FIXTURE.read_text())
    assert len(source.CASES) == len(frozen['traces']) == len(frozen['successor_roots'])
    for (family, ordinal, _), trace in zip(source.CASES, frozen['traces']):
        original = importlib.import_module('current_stf_'+family+'_oracle')
        assert trace['family'] == family and trace['profile'] == original.PROFILES[ordinal]
        selected = profiles((family,))
        assert 0 <= ordinal < len(selected)
        result.append(selected[ordinal]) # Explicit source case binding precedes target startup; no observed state selects Parameters.
    return result
