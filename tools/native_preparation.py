"""Shared native libraries and independent fixtures for both supported unit entry points."""
import hashlib
import sys
from setup_nimony import ROOT
from native_fixtures import (
    unit_runtime_fixtures, unit_store_fixture, unit_authorization_fixture, unit_history_fixture,
    unit_signing_fixture, unit_entropy_fixture, unit_validator_fixture, unit_ticket_fixture,
    unit_sealer_fixture,
)


# Let standalone callers persist completed stages immediately, including before a later failure.
def record_evidence(record, name, evidence):
    if record is not None:
        # Cumulative callers keep the returned mapping; standalone callers supply a file writer.
        record(name, evidence)


# Prepare pristine pinned libraries once, retaining each provider's original evidence fields.
def prepare_libraries(folder, record=None):
    sys.path.insert(0, str(ROOT/'tests'))
    from nimony_crypto import prepare as prepare_crypto
    from bandersnatch_native import prepare as prepare_bandersnatch
    from nimony_quic import prepare as prepare_quic
    crypto, observer, crypto_evidence = prepare_crypto(folder)
    record_evidence(record, 'crypto_native', crypto_evidence)
    bs, bs_observer, bs_evidence = prepare_bandersnatch(folder)
    record_evidence(record, 'bandersnatch_native', bs_evidence)
    quic, certificates, quic_evidence = prepare_quic()
    record_evidence(record, 'quic_native', quic_evidence)
    libraries = dict(crypto=crypto, observer=observer, bandersnatch=bs,
                     bandersnatch_observer=bs_observer, quic=quic)
    return libraries, certificates, dict(crypto_native=crypto_evidence,
        bandersnatch_native=bs_evidence, quic_native=quic_evidence)


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
