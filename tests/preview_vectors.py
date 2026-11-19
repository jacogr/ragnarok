# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Read selected unreleased preview blobs separately from supervisor-era vector evidence."""
import hashlib
import json
import subprocess
from test_support import ROOT


# Select the same report policy and accumulation scenarios in both populations.
REPORT_GAS_CASES = (
    'big_bundle_high_auth_gas-1', 'high_work_report_gas-1',
    'refine_load_at_report_limits-1', 'too_big_bundle-1',
    'too_high_auth_gas-1', 'too_high_refine_load-1', 'too_high_work_report_gas-1',
)
ACCUMULATION_GAS_CASES = (
    'recreate_ejected_service_by_higher_registrar-1',
    'recreate_ejected_service_that_accumulates-1',
    'recreate_service_ejected_in_earlier_round-1',
    'transfer_for_service_ejected_in_same_round_high_ejector-1',
    'transfer_for_service_ejected_in_same_round_low_ejector-1',
)
ACCUMULATION_SUPERVISION_CASES = (
    'deferred_transfer_to_junior_is_delivered-1',
    'discarded_junior_creates_no_service-1',
    'discarded_junior_keeps_provisions-1',
    'discarded_manager_privileges_revert-1',
    'recreate_ejected_service-1',
    'service_reads_transfers_before_work_digests-1',
    'supervisor_modification_discards_junior_results-1',
    'supervisor_modification_discards_junior_results_control-1',
)


def accumulation_cases(profile):
    """Name the selected paired recreation, transfer and conflict inputs for one population."""
    return tuple(f'stf/accumulate/{profile}/{name}'
                 for name in ACCUMULATION_GAS_CASES + ACCUMULATION_SUPERVISION_CASES)


def pins():
    """Return the explicit preview identity; the vendor checkout remains the historical profile."""
    return json.loads((ROOT/'spec/pins.json').read_bytes())['vectors_preview']


def blob(path):
    """Verify an immutable blob before decoding its schema or comparing its native result."""
    source = pins()
    raw = subprocess.check_output(['git', '-C', str(ROOT/source['path']),
                                   'show', source['commit']+':'+path])
    assert hashlib.sha256(raw).hexdigest() == source['git_blobs'][path], path
    return raw
