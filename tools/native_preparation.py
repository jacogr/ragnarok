# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Shared native libraries and independent fixtures for both supported unit entry points.

Exposes prepare_libraries, prepare_integration, prepare_unit_fixtures and record_evidence for
shared native setup, plus dependency-scoped selected-suite preparation.
"""
import hashlib
import sys
from setup_nimony import ROOT
from native_fixtures import (
    unit_runtime_fixtures, unit_store_fixture, unit_authorization_fixture, unit_history_fixture,
    unit_signing_fixture, unit_entropy_fixture, unit_validator_fixture, unit_ticket_fixture,
    unit_sealer_fixture, unit_pvm_gas_fixture, unit_pvm_step_fixture,
)


# Let standalone callers persist completed stages immediately, including before a later failure.
def record_evidence(record, name, evidence):
    if record is not None:
        # Cumulative callers keep the returned mapping; standalone callers supply a file writer.
        record(name, evidence)


# Prepare pristine pinned libraries once, retaining each provider's original evidence fields.
def prepare_libraries(folder, record=None, required=None):
    available = {'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic'}
    requested = available if required is None else set(required)
    if not requested <= available:
        # Refuse unknown providers before any native build or partial evidence is published.
        raise ValueError('Unknown native library profile')
    sys.path.insert(0, str(ROOT/'tests'))
    libraries, evidence, certificates = {}, {}, None
    if requested.intersection({'crypto', 'observer'}):
        # Production and observed crypto share one provider; skip unrelated Rust/transport providers.
        from nimony_crypto import prepare as prepare_crypto
        crypto, observer, evidence['crypto_native'] = prepare_crypto(folder)
        record_evidence(record, 'crypto_native', evidence['crypto_native'])
        libraries.update(crypto=crypto, observer=observer)
    if requested.intersection({'bandersnatch', 'bandersnatch_observer'}):
        # The Rust provider owns both ABI profiles and its unchanged release verification.
        from bandersnatch_native import prepare as prepare_bandersnatch
        bs, bs_observer, evidence['bandersnatch_native'] = prepare_bandersnatch(folder)
        record_evidence(record, 'bandersnatch_native', evidence['bandersnatch_native'])
        libraries.update(bandersnatch=bs, bandersnatch_observer=bs_observer)
    if 'quic' in requested:
        # Only transport consumers need the QUIC build and its generated certificates.
        from nimony_quic import prepare as prepare_quic
        libraries['quic'], certificates, evidence['quic_native'] = prepare_quic()
        record_evidence(record, 'quic_native', evidence['quic_native'])
    return {name: library for name, library in libraries.items() if name in requested}, certificates, evidence


# Generate the same CE corpus and altered reload candidates without compiling any peer or driver.
def prepare_integration(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    import test_integration as integration_fixture
    integration_fixture.BUILD.mkdir(parents=True, exist_ok=True)
    wires, keys = integration_fixture.corpus()
    reload = folder/'integration-reload'
    reload.mkdir(exist_ok=True)
    for index in range(8):
        # A changed first byte exposes a refused reload that partially publishes candidate data.
        wire = bytearray((wires/(str(index)+'.bin')).read_bytes())
        wire[0] ^= 128
        (reload/(str(index)+'.bin')).write_bytes(wire)
    evidence = dict(keys=keys,
        original={str(index): hashlib.sha256((wires/(str(index)+'.bin')).read_bytes()).hexdigest() for index in range(8)},
        reload={str(index): hashlib.sha256((reload/(str(index)+'.bin')).read_bytes()).hexdigest() for index in range(8)})
    return wires, reload, evidence


# Assemble fresh feature manifests in the original order; reports retain their historical field names.
def prepare_unit_fixtures(folder, certificates, wires, reload, record=None):
    fixtures = unit_runtime_fixtures(certificates, wires, reload)
    evidence = {}
    step, evidence['pvm_step_fixture'] = unit_pvm_step_fixture(folder)
    fixtures.update(step)
    record_evidence(record, 'pvm_step_fixture', evidence['pvm_step_fixture'])
    gas, evidence['pvm_gas_fixture'] = unit_pvm_gas_fixture(folder)
    fixtures.update(gas)
    record_evidence(record, 'pvm_gas_fixture', evidence['pvm_gas_fixture'])
    store, evidence['store_replay_fixture'] = unit_store_fixture(folder)
    record_evidence(record, 'store_replay_fixture', evidence['store_replay_fixture'])
    fixtures.update(store)
    authorization, evidence['authorization_stf_fixture'] = unit_authorization_fixture(folder)
    record_evidence(record, 'authorization_stf_fixture', evidence['authorization_stf_fixture'])
    fixtures.update(authorization)
    history, evidence['history_stf_fixture'] = unit_history_fixture(folder)
    record_evidence(record, 'history_stf_fixture', evidence['history_stf_fixture'])
    fixtures.update(history)
    signing, evidence['signing_domain_fixture'] = unit_signing_fixture(folder)
    record_evidence(record, 'signing_domain_fixture', evidence['signing_domain_fixture'])
    fixtures.update(signing)
    entropy, evidence['entropy_stf_fixture'] = unit_entropy_fixture(folder)
    record_evidence(record, 'entropy_stf_fixture', evidence['entropy_stf_fixture'])
    fixtures.update(entropy)
    validator, evidence['validator_stf_fixture'] = unit_validator_fixture(folder)
    ticket, evidence['ticket_stf_fixture'] = unit_ticket_fixture(folder)
    record_evidence(record, 'ticket_stf_fixture', evidence['ticket_stf_fixture'])
    fixtures.update(validator)
    fixtures.update(ticket)
    sealer, evidence['sealer_stf_fixture'] = unit_sealer_fixture(folder)
    record_evidence(record, 'sealer_stf_fixture', evidence['sealer_stf_fixture'])
    fixtures.update(sealer)
    record_evidence(record, 'validator_stf_fixture', evidence['validator_stf_fixture'])
    return fixtures, evidence


# Provider aliases describe actual sharing; coverage is checked independently against prepared suite profiles.
SELECTED_FIXTURE_GROUPS = {
    'accumulation_context': ('accumulation_context',),
    'accumulation_credit': ('accumulation_credit',),
    'accumulation_inputs': ('accumulation_inputs',),
    'accumulation_invocation': ('accumulation_invocation',),
    'accumulation_operands': ('accumulation_operands',),
    'accumulation_queue': ('accumulation_queue',),
    'accumulation_round': ('accumulation_round',),
    'accumulation_service': ('accumulation_service', 'accumulation_skip'),
    'admission': ('block_admission', 'report_admission', 'report_transition'),
    'authentication': ('safrole_auth_state', 'safrole_authentication'),
    'authorization': ('authorization_transition',),
    'availability': ('availability_transition',),
    'commitment': ('extrinsic_commitment',),
    'disputes': ('disputes_transition',),
    'entropy': ('entropy_transition',),
    'guarantee_credentials': ('guarantee_credentials',),
    'guarantors': ('guarantor_assignments',),
    'history': ('history_transition',),
    'markers': ('marker_state', 'safrole_markers'),
    'preimage_transition': ('preimage_transition',),
    'pvm_gas': ('pvm_gas',),
    'pvm_step': ('pvm_step',),
    'report_anchors': ('report_anchors',),
    'report_assignments': ('report_assignments',),
    'report_packages': ('report_packages',),
    'report_policy': ('report_policy',),
    'schedule': ('sealer_schedule', 'sealer_state'),
    'signing': ('signing_domains',),
    'store': ('state_store_replay',),
    'ticket': ('ticket_admission', 'ticket_state'),
    'transition': ('safrole_transition',),
    'validator': ('validator_rotation', 'validator_state'),
}


# Prepare only one suite's existing independent fixture, keeping its complete manifest/hash contract.
def prepare_selected_fixture(folder, suite, certificates=None, record=None):
    if suite == 'quic_transport':
        # Transport needs certificates only; no CE corpus or reload candidates are generated.
        fixtures = unit_runtime_fixtures(certificates, None, None, suite=suite)
        evidence = {'files': {str(path): digest for path, digest in fixtures[suite][2]}}
    elif suite == 'quic_integration':
        # CE integration needs original/reload bytes only; no unused certificate/QUIC preparation.
        wires, reload, evidence = prepare_integration(folder)
        fixtures = unit_runtime_fixtures(None, wires, reload, suite=suite)
    else:
        # Resolve aliases explicitly and refuse an omitted provider rather than reuse stale generated input.
        group = next((name for name, suites in SELECTED_FIXTURE_GROUPS.items() if suite in suites), None)
        if group is None:
            raise ValueError('No selected fixture provider: '+suite)
        import native_fixtures
        fixtures, evidence = getattr(native_fixtures, 'unit_'+group+'_fixture')(folder)
    if suite not in fixtures:
        # A provider returning a sibling fixture cannot satisfy the requested suite.
        raise ValueError('Missing selected fixture manifest: '+suite)
    record_evidence(record, 'selected_unit_fixture', evidence)
    return {suite: fixtures[suite]}, evidence
