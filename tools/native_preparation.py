# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Shared native libraries and independent fixtures for both supported unit entry points.

Exposes prepare_libraries, prepare_integration, prepare_unit_fixtures and record_evidence for
shared native setup, plus dependency-scoped selected-suite and partition preparation.
"""
import hashlib
import sys
from setup_nimony import ROOT
from native_fixtures import PROVIDERS, unit_runtime_fixtures


# Let standalone callers persist completed stages immediately, including before a later failure.
def record_evidence(record, name, evidence):
    if record is not None:
        # Cumulative callers keep the returned mapping; standalone callers supply a file writer.
        record(name, evidence)


# Prepare pristine pinned libraries once, retaining each provider's original evidence fields.
def prepare_libraries(folder, record=None, required=None):
    available = {'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic', 'storage_io'}
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
    if 'storage_io' in requested:
        # This test-only object never participates in production crypto, transport or executable builds.
        from storage_io_observer import prepare as prepare_storage_io
        libraries['storage_io'], evidence['storage_io_native'] = prepare_storage_io(folder)
        record_evidence(record, 'storage_io_native', evidence['storage_io_native'])
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
    evidence, deferred = {}, []
    for provider in PROVIDERS.plan('root'):
        # Each completed stage publishes evidence before the next one, except explicitly deferred legacy writes.
        fresh, observed = provider.prepare(folder)
        if fixtures.keys() & fresh.keys():
            raise ValueError('Duplicate native fixture consumers: '+provider.name)
        fixtures.update(fresh)
        key = provider.evidence[0]
        evidence[key] = observed
        if provider.deferred:
            deferred.append((key, observed))
        else:
            record_evidence(record, key, observed)
    for key, observed in deferred:
        # The validator stage historically publishes its evidence after the nested sealer aggregate.
        record_evidence(record, key, observed)
    return fixtures, evidence


# Run one existing feature provider, preserving its sibling manifests for batched selection.
def _selected_fixture_provider(folder, suite, certificates, integration=None):
    from native_requirements import NATIVE_REQUIREMENTS
    name = NATIVE_REQUIREMENTS.get(suite, {}).get('provider')
    provider = PROVIDERS.providers.get(name)
    if provider is None or not provider.variants:
        raise ValueError('No selected fixture provider: '+suite)
    generated = None
    if 'integration' in provider.inputs and integration is None:
        # Only consumers declaring CE inputs prepare the corpus; existing partition inputs are reused unchanged.
        wires, reload, generated = prepare_integration(folder)
        integration = (wires, reload)
    fixtures, evidence = provider.prepare(folder, certificates=certificates, integration=integration)
    if generated is not None:
        # A fresh CE preparation retains its historical original/reload generation evidence.
        evidence = generated
    if suite not in fixtures:
        # A provider returning a sibling fixture cannot satisfy the requested suite.
        raise ValueError('Missing selected fixture manifest: '+suite)
    return fixtures, evidence


# Prepare only one suite's existing independent fixture, keeping its complete manifest/hash contract.
def prepare_selected_fixture(folder, suite, certificates=None, record=None):
    fixtures, evidence = _selected_fixture_provider(folder, suite, certificates)
    record_evidence(record, 'selected_unit_fixture', evidence)
    return {suite: fixtures[suite]}, evidence


# Prepare each selected feature provider once, reusing its complete manifests for sibling suites.
def prepare_partition_fixtures(folder, suites, certificates=None, integration=None):
    from native_requirements import NATIVE_REQUIREMENTS
    selected = [suite for suite in suites if NATIVE_REQUIREMENTS[suite]['prepared']]
    fixtures, evidence = {}, {}
    for suite in selected:
        # A preceding provider may already have produced this sibling's fresh hash contract.
        if suite in fixtures:
            continue
        if integration is None:
            # Default selected calls retain their existing API and prepare only required resources.
            fresh, observed = _selected_fixture_provider(folder, suite, certificates)
        else:
            # The corpus-owning partition supplies its existing original/reload inputs to any declaring provider.
            fresh, observed = _selected_fixture_provider(folder, suite, certificates, integration=integration)
        fixtures.update(fresh)
        evidence[suite] = observed
    missing = set(selected)-set(fixtures)
    if missing:
        # A provider omission must fail before a suite can inherit old fixture environment variables.
        raise ValueError('Missing partition fixture manifests: '+', '.join(sorted(missing)))
    return {suite: fixtures[suite] for suite in selected}, evidence
