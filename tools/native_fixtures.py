# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned native fixture preparation; independent oracles retain their byte contracts.

Exposes unit_*_fixture adapters that return native-suite environment manifests and hashed
evidence. PROVIDERS declarations own execution order, input resources and report metadata;
unit_sealer_fixture and unit_runtime_fixtures retain aggregate preparation APIs.
"""
import sys
import hashlib
from setup_nimony import ROOT
from native_fixture_providers import PROVIDERS


# Prepare independent schedule inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=10)
def unit_schedule_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from sealer_schedule_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SEALER_SCHEDULE', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent markers inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=20)
def unit_markers_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from safrole_marker_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SAFROLE_MARKERS', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent authentication inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=30)
def unit_authentication_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from safrole_authentication_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SAFROLE_AUTHENTICATION', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent transition inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=40)
def unit_transition_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from safrole_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SAFROLE_TRANSITION', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent commitment inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=50)
def unit_commitment_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from block_admission_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_EXTRINSIC_COMMITMENT', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent admission inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=150, variants=('default', 'report'))
def unit_admission_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from block_admission_fixtures import prepare_admission
    path, evidence = prepare_admission(folder)
    fixture = ('RAGNAROK_BLOCK_ADMISSION', path, ((path, evidence['fixture_sha256']),))
    template = ROOT/'tests/fixtures/state-report.bin'
    report_fixture = (None, {'RAGNAROK_BLOCK_ADMISSION': path, 'RAGNAROK_STATE_REPORT': template},
                      ((path, evidence['fixture_sha256']),
                       (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'default': fixture, 'report': report_fixture}, evidence


# Prepare pin-checked preimage STF account/statistics projections for the native transition suite.
@PROVIDERS.fixture(group='sealer', order=60)
def unit_preimage_transition_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from preimage_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_PREIMAGE_TRANSITION', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent incoming-credit balances, metadata and complete embedding-map root witnesses.
@PROVIDERS.fixture(group='sealer', order=70)
def unit_accumulation_credit_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_credit_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_ACCUMULATION_CREDIT', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Supply the pinned signed-block template to native initial-context assertions without a new oracle.
@PROVIDERS.fixture(group='sealer', order=80)
def unit_accumulation_context_fixture(folder):
    template = ROOT/'tests/fixtures/state-report.bin'
    digest = '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371'
    fixture = ('RAGNAROK_STATE_REPORT', template, ((template, digest),))
    return {'default': fixture}, {'fixture_sha256': digest}


# Pair independent queue expectations with the existing original report/block fixture contracts.
@PROVIDERS.fixture(group='sealer', order=140)
def unit_accumulation_queue_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_queue_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_QUEUE': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'default': fixture}, evidence


# Prepare exact report-prefix operand expectations without invoking any production planner.
@PROVIDERS.fixture(group='sealer', order=130)
def unit_accumulation_operands_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_operand_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_OPERANDS': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'default': fixture}, evidence


# Prepare independent invocation contexts while retaining the original report/prefix fixture identities.
@PROVIDERS.fixture(group='sealer', order=120)
def unit_accumulation_inputs_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_input_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_ACCUMULATION_INPUTS', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent initial-accseq gas prefixes, preserving signed-fixture template identity.
@PROVIDERS.fixture(group='sealer', order=110)
def unit_accumulation_round_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_round_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_ROUND': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'default': fixture}, evidence


# Prepare independent service-code envelopes and preserve the original signed-report template hash.
@PROVIDERS.fixture(group='sealer', order=100)
def unit_accumulation_service_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_service_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_SERVICE': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'default': fixture}, evidence


# Prepare independent compact invocation bytes, ID witnesses and the signed-report template identity.
@PROVIDERS.fixture(group='sealer', order=90)
def unit_accumulation_invocation_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_invocation_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_INVOCATION': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'default': fixture}, evidence


# Prepare independent disputes inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=160)
def unit_disputes_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from disputes_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_DISPUTES_TRANSITION', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent availability inputs and expose their hashes to the consuming native suites.
@PROVIDERS.fixture(group='sealer', order=170)
def unit_availability_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from availability_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_AVAILABILITY_TRANSITION', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare independent guarantor assignment inputs and retain the published fixture hash.
@PROVIDERS.fixture(group='sealer', order=180)
def unit_guarantors_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from guarantor_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_GUARANTORS', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare unchanged credential projections independently from other report-state fixture families.
@PROVIDERS.fixture(group='sealer', order=190)
def unit_guarantee_credentials_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from guarantee_credential_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_GUARANTEE_CREDENTIALS', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare original report-policy projections with native ownership of every verdict.
@PROVIDERS.fixture(group='sealer', order=200)
def unit_report_policy_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_policy_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_POLICY', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Transport original recent-anchor inputs without inventing unavailable external ancestor headers.
@PROVIDERS.fixture(group='sealer', order=210)
def unit_report_anchors_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_anchor_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_ANCHORS', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Preserve the STF's summarized known set without manufacturing omitted pipeline chapters.
@PROVIDERS.fixture(group='sealer', order=220)
def unit_report_packages_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_package_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_PACKAGES', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Transport exact original report STF C(10) inputs and expected assignment candidates.
@PROVIDERS.fixture(group='sealer', order=230)
def unit_report_assignments_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_assignment_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_ASSIGNMENTS', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Keep the historical preparation order and nested report schema for existing evidence consumers.
@PROVIDERS.fixture(group='root', order=100,
                   evidence=('sealer_stf_fixture', 'sealer-preparation'), aggregate=True)
def unit_sealer_fixture(folder):
    fixtures, rows = {}, []
    for provider in PROVIDERS.plan('sealer'):
        # Keep every feature's execution rank and reject one provider overwriting another's consumers.
        fresh, observed = provider.prepare(folder)
        if fixtures.keys() & fresh.keys():
            raise ValueError('Duplicate nested fixture consumers: '+provider.name)
        fixtures.update(fresh)
        rows.append((provider.name, observed))
    if not rows:
        # A missing pipeline cannot produce empty successful sealer evidence.
        raise ValueError('Empty sealer fixture plan')
    # Historical evidence exposes schedule fields directly, then nests later features in reverse order.
    evidence = dict(rows[0][1])
    for name, observed in reversed(rows[1:]):
        if name in evidence:
            raise ValueError('Duplicate nested fixture evidence: '+name)
        evidence[name] = observed
    return fixtures, evidence



# Prepare published storage bytes once per invocation; native assertions own all store verdicts.
@PROVIDERS.fixture(group='root', order=30, evidence=('store_replay_fixture', 'store-preparation'))
def unit_store_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from state_store_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_STORE_REPLAY', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Admission fixtures contain upstream proof/accumulator values, not a Python implementation of selection.
@PROVIDERS.fixture(group='root', order=90, evidence=('ticket_stf_fixture', 'ticket-preparation'))
def unit_ticket_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from ticket_admission_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_TICKET_ADMISSION', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare exact published roster projections for the bounded planner's native assertions.
@PROVIDERS.fixture(group='root', order=80,
                   evidence=('validator_stf_fixture', 'validator-preparation'), deferred=True)
def unit_validator_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from validator_rotation_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_VALIDATOR_STF', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare only the published entropy/time projections, keeping full Safrole execution outside this suite.
@PROVIDERS.fixture(group='root', order=70, evidence=('entropy_stf_fixture', 'entropy-preparation'))
def unit_entropy_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from entropy_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_ENTROPY_STF', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare public upstream credentials with independent OpenSSL positive/old-domain verdicts.
@PROVIDERS.fixture(group='root', order=60,
                   evidence=('signing_domain_fixture', 'signing-preparation'))
def unit_signing_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from signing_domain_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SIGNING_DOMAINS', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare published history cases and independent output-tree commitments for native assertions.
@PROVIDERS.fixture(group='root', order=50, evidence=('history_stf_fixture', 'history-preparation'))
def unit_history_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from history_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_HISTORY_STF', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Prepare complete pinned authorization STF cases; the native suite executes and asserts the subsystem.
@PROVIDERS.fixture(group='root', order=40,
                   evidence=('authorization_stf_fixture', 'authorization-preparation'))
def unit_authorization_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from authorization_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_AUTHORIZATION_STF', path, ((path, evidence['fixture_sha256']),))
    return {'default': fixture}, evidence


# Fresh transport identities serve ordinary QUIC consumers without generating CE inputs.
@PROVIDERS.fixture(group='runtime', order=10, inputs=('certificates',))
def unit_transport_fixture(folder, certificates):
    inputs = {'RAGNAROK_TEST_CERT': certificates/'a.cert.pem',
              'RAGNAROK_TEST_KEY': certificates/'a.key.pem'}
    files = tuple((path, hashlib.sha256(path.read_bytes()).hexdigest()) for path in inputs.values())
    return {'default': (None, inputs, files)}, {'files': {str(path): digest for path, digest in files}}


# The block requester additionally pins its independent signed-report template.
@PROVIDERS.fixture(group='runtime', order=20, inputs=('certificates',))
def unit_block_download_fixture(folder, certificates):
    report = ROOT/'tests/fixtures/state-report.bin'
    inputs = {'RAGNAROK_STATE_REPORT': report,
              'RAGNAROK_TEST_CERT': certificates/'a.cert.pem',
              'RAGNAROK_TEST_KEY': certificates/'a.key.pem'}
    files = tuple((path, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371'
                   if path == report else hashlib.sha256(path.read_bytes()).hexdigest())
                  for path in inputs.values())
    return {'default': (None, inputs, files)}, {'files': {str(path): digest for path, digest in files}}


# Pin both independent server identities for the bounded download catalog and dispatcher.
@PROVIDERS.fixture(group='runtime', order=25, inputs=('certificates',))
def unit_download_peers_fixture(folder, certificates):
    """Return the signed-report and two-identity manifest without suite-name dispatch."""
    report = ROOT/'tests/fixtures/state-report.bin'
    inputs = {'RAGNAROK_STATE_REPORT': report,
              'RAGNAROK_TEST_CERT': certificates/'a.cert.pem',
              'RAGNAROK_TEST_CERT_B': certificates/'b.cert.pem',
              'RAGNAROK_TEST_KEY': certificates/'a.key.pem',
              'RAGNAROK_TEST_KEY_B': certificates/'b.key.pem',
              'RAGNAROK_TEST_PEER_A': certificates/'a.pub',
              'RAGNAROK_TEST_PEER_B': certificates/'b.pub'}
    files = tuple((path, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371'
                   if path == report else hashlib.sha256(path.read_bytes()).hexdigest())
                  for path in inputs.values())
    return {'default': (None, inputs, files)}, {'files': {str(path): digest for path, digest in files}}


# Every CE child retains its original/reload byte identity, including later siblings.
@PROVIDERS.fixture(group='runtime', order=30, inputs=('integration',))
def unit_integration_fixture(folder, integration):
    original, reload = integration
    inputs = {'RAGNAROK_TEST_WIRES': original, 'RAGNAROK_TEST_RELOAD': reload}
    files = tuple((directory/(str(index)+'.bin'),
                   hashlib.sha256((directory/(str(index)+'.bin')).read_bytes()).hexdigest())
                  for directory in (original, reload) for index in range(8))
    return {'default': (None, inputs, files)}, {'files': {str(path): digest for path, digest in files}}


# Retain the aggregate runtime API while discovering its consumers from their own requirements.
def unit_runtime_fixtures(certificates, original, reload, suite=None):
    from native_requirements import NATIVE_REQUIREMENTS
    providers = PROVIDERS.plan('runtime')
    if suite is not None:
        # A selected runtime consumer must declare a provider with the appropriate resource contract.
        name = NATIVE_REQUIREMENTS.get(suite, {}).get('provider')
        providers = [provider for provider in providers if provider.name == name]
        if not providers:
            raise ValueError('Unknown runtime fixture suite: '+suite)
    fixtures = {}
    for provider in providers:
        # Runtime registration preserves certificate-before-CE ordering without a suite-name branch table.
        fresh, _ = provider.prepare(ROOT/'build', certificates=certificates, integration=(original, reload))
        if fixtures.keys() & fresh.keys():
            raise ValueError('Duplicate runtime fixture consumers: '+provider.name)
        fixtures.update(fresh)
    return fixtures if suite is None else {suite: fixtures[suite]}


# Generate full/tiny/resized complete-state bytes independently without checking in large full-profile copies.
@PROVIDERS.fixture(group='root', order=110,
                   evidence=('serialization_profiles_fixture', 'serialization-profiles-preparation'))
def unit_serialization_profiles_fixture(folder):
    """Bind authored current-schema complete maps to their exact generated byte identity."""
    sys.path.insert(0, str(ROOT/'tests'))
    from state_serialization_profiles_oracle import prepare
    path, evidence = prepare(folder)
    return {'default': ('RAGNAROK_SERIALIZATION_PROFILES', path,
                        ((path, evidence['fixture_sha256']),))}, evidence


# Generate gas inputs under the caller's ignored build directory from pinned submodule witnesses.
@PROVIDERS.fixture(group='root', order=20, evidence=('pvm_gas_fixture', 'pvm-gas-preparation'))
def unit_pvm_gas_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from pvm_gas_reference import prepare
    path, evidence = prepare(folder)
    return {'default': ('RAGNAROK_PVM_GAS', path, ((path, evidence['fixture_sha256']),))}, evidence


# Generate composed stepping traces in build storage without adding checked-in binary copies.
@PROVIDERS.fixture(group='root', order=10, evidence=('pvm_step_fixture', 'pvm-step-preparation'))
def unit_pvm_step_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from pvm_step_reference import prepare
    path, evidence = prepare(folder)
    return {'default': ('RAGNAROK_PVM_STEP', path, ((path, evidence['fixture_sha256']),))}, evidence
