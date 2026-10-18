# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned native fixture preparation; independent oracles retain their byte contracts.

Exposes unit_*_fixture adapters that return native-suite environment manifests and hashed
evidence, plus unit_sealer_fixture aggregation and unit_runtime_fixtures for QUIC transport.
"""
import sys
import hashlib
from setup_nimony import ROOT


# Prepare independent schedule inputs and expose their hashes to the consuming native suites.
def unit_schedule_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from sealer_schedule_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SEALER_SCHEDULE', path, ((path, evidence['fixture_sha256']),))
    return {'sealer_schedule': fixture, 'sealer_state': fixture}, evidence


# Prepare independent markers inputs and expose their hashes to the consuming native suites.
def unit_markers_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from safrole_marker_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SAFROLE_MARKERS', path, ((path, evidence['fixture_sha256']),))
    return {'safrole_markers': fixture, 'marker_state': fixture}, evidence


# Prepare independent authentication inputs and expose their hashes to the consuming native suites.
def unit_authentication_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from safrole_authentication_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SAFROLE_AUTHENTICATION', path, ((path, evidence['fixture_sha256']),))
    return {'safrole_authentication': fixture, 'safrole_auth_state': fixture}, evidence


# Prepare independent transition inputs and expose their hashes to the consuming native suites.
def unit_transition_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from safrole_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SAFROLE_TRANSITION', path, ((path, evidence['fixture_sha256']),))
    return {'safrole_transition': fixture}, evidence


# Prepare independent commitment inputs and expose their hashes to the consuming native suites.
def unit_commitment_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from block_admission_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_EXTRINSIC_COMMITMENT', path, ((path, evidence['fixture_sha256']),))
    return {'extrinsic_commitment': fixture}, evidence


# Prepare independent admission inputs and expose their hashes to the consuming native suites.
def unit_admission_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from block_admission_fixtures import prepare_admission
    path, evidence = prepare_admission(folder)
    fixture = ('RAGNAROK_BLOCK_ADMISSION', path, ((path, evidence['fixture_sha256']),))
    template = ROOT/'tests/fixtures/state-report.bin'
    report_fixture = (None, {'RAGNAROK_BLOCK_ADMISSION': path, 'RAGNAROK_STATE_REPORT': template},
                      ((path, evidence['fixture_sha256']),
                       (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'block_admission': fixture, 'report_admission': report_fixture, 'report_transition': report_fixture}, evidence


# Pair independent queue expectations with the existing original report/block fixture contracts.
def unit_accumulation_queue_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_queue_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_QUEUE': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'accumulation_queue': fixture}, evidence


# Prepare exact report-prefix operand expectations without invoking any production planner.
def unit_accumulation_operands_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_operand_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_OPERANDS': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'accumulation_operands': fixture}, evidence


# Prepare independent invocation contexts while retaining the original report/prefix fixture identities.
def unit_accumulation_inputs_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_input_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_ACCUMULATION_INPUTS', path, ((path, evidence['fixture_sha256']),))
    return {'accumulation_inputs': fixture}, evidence


# Prepare independent initial-accseq gas prefixes, preserving signed-fixture template identity.
def unit_accumulation_round_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_round_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_ROUND': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'accumulation_round': fixture}, evidence


# Prepare independent service-code envelopes and preserve the original signed-report template hash.
def unit_accumulation_service_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from accumulation_service_fixtures import prepare
    path, evidence = prepare(folder)
    template = ROOT/'tests/fixtures/state-report.bin'
    fixture = (None, {'RAGNAROK_ACCUMULATION_SERVICE': path, 'RAGNAROK_STATE_REPORT': template},
               ((path, evidence['fixture_sha256']),
                (template, '3ea13ab83a1db73fd4be6f741729e9fb70771610d3d780e46cfae8b0722ac371')))
    return {'accumulation_service': fixture}, evidence


# Prepare independent disputes inputs and expose their hashes to the consuming native suites.
def unit_disputes_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from disputes_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_DISPUTES_TRANSITION', path, ((path, evidence['fixture_sha256']),))
    return {'disputes_transition': fixture}, evidence


# Prepare independent availability inputs and expose their hashes to the consuming native suites.
def unit_availability_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from availability_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_AVAILABILITY_TRANSITION', path, ((path, evidence['fixture_sha256']),))
    return {'availability_transition': fixture}, evidence


# Prepare independent guarantor assignment inputs and retain the published fixture hash.
def unit_guarantors_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from guarantor_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_GUARANTORS', path, ((path, evidence['fixture_sha256']),))
    return {'guarantor_assignments': fixture}, evidence


# Prepare unchanged credential projections independently from other report-state fixture families.
def unit_guarantee_credentials_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from guarantee_credential_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_GUARANTEE_CREDENTIALS', path, ((path, evidence['fixture_sha256']),))
    return {'guarantee_credentials': fixture}, evidence


# Prepare original report-policy projections with native ownership of every verdict.
def unit_report_policy_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_policy_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_POLICY', path, ((path, evidence['fixture_sha256']),))
    return {'report_policy': fixture}, evidence


# Transport original recent-anchor inputs without inventing unavailable external ancestor headers.
def unit_report_anchors_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_anchor_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_ANCHORS', path, ((path, evidence['fixture_sha256']),))
    return {'report_anchors': fixture}, evidence


# Preserve the STF's summarized known set without manufacturing omitted pipeline chapters.
def unit_report_packages_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_package_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_PACKAGES', path, ((path, evidence['fixture_sha256']),))
    return {'report_packages': fixture}, evidence


# Transport exact original report STF C(10) inputs and expected assignment candidates.
def unit_report_assignments_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from report_assignment_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_REPORT_ASSIGNMENTS', path, ((path, evidence['fixture_sha256']),))
    return {'report_assignments': fixture}, evidence


# Keep the historical preparation order and nested report schema for existing evidence consumers.
def unit_sealer_fixture(folder):
    fixtures, evidence = unit_schedule_fixture(folder)
    markers_fixtures, markers_evidence = unit_markers_fixture(folder)
    fixtures.update(markers_fixtures)
    authentication_fixtures, authentication_evidence = unit_authentication_fixture(folder)
    fixtures.update(authentication_fixtures)
    transition_fixtures, transition_evidence = unit_transition_fixture(folder)
    fixtures.update(transition_fixtures)
    commitment_fixtures, commitment_evidence = unit_commitment_fixture(folder)
    fixtures.update(commitment_fixtures)
    service_fixtures, service_evidence = unit_accumulation_service_fixture(folder)
    fixtures.update(service_fixtures)
    round_fixtures, round_evidence = unit_accumulation_round_fixture(folder)
    fixtures.update(round_fixtures)
    input_fixtures, input_evidence = unit_accumulation_inputs_fixture(folder)
    fixtures.update(input_fixtures)
    operand_fixtures, operand_evidence = unit_accumulation_operands_fixture(folder)
    fixtures.update(operand_fixtures)
    queue_fixtures, queue_evidence = unit_accumulation_queue_fixture(folder)
    fixtures.update(queue_fixtures)
    admission_fixtures, admission_evidence = unit_admission_fixture(folder)
    fixtures.update(admission_fixtures)
    disputes_fixtures, disputes_evidence = unit_disputes_fixture(folder)
    fixtures.update(disputes_fixtures)
    availability_fixtures, availability_evidence = unit_availability_fixture(folder)
    fixtures.update(availability_fixtures)
    guarantors_fixtures, guarantors_evidence = unit_guarantors_fixture(folder)
    fixtures.update(guarantors_fixtures)
    credential_fixtures, credential_evidence = unit_guarantee_credentials_fixture(folder)
    fixtures.update(credential_fixtures)
    policy_fixtures, policy_evidence = unit_report_policy_fixture(folder)
    fixtures.update(policy_fixtures)
    anchor_fixtures, anchor_evidence = unit_report_anchors_fixture(folder)
    fixtures.update(anchor_fixtures)
    package_fixtures, package_evidence = unit_report_packages_fixture(folder)
    fixtures.update(package_fixtures)
    assignment_fixtures, assignment_evidence = unit_report_assignments_fixture(folder)
    fixtures.update(assignment_fixtures)
    evidence['report_assignments'] = assignment_evidence
    evidence['report_packages'] = package_evidence
    evidence['report_anchors'] = anchor_evidence
    evidence['report_policy'] = policy_evidence
    evidence['guarantee_credentials'] = credential_evidence
    evidence['guarantors'] = guarantors_evidence
    evidence['availability'] = availability_evidence
    evidence['disputes'] = disputes_evidence
    evidence['admission'] = admission_evidence
    evidence['accumulation_queue'] = queue_evidence
    evidence['accumulation_operands'] = operand_evidence
    evidence['accumulation_inputs'] = input_evidence
    evidence['accumulation_round'] = round_evidence
    evidence['accumulation_service'] = service_evidence
    evidence['commitment'] = commitment_evidence
    evidence['transition'] = transition_evidence
    evidence['authentication'] = authentication_evidence
    evidence['markers'] = markers_evidence
    return fixtures, evidence


# Prepare published storage bytes once per invocation; native assertions own all store verdicts.
def unit_store_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from state_store_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_STORE_REPLAY', path, ((path, evidence['fixture_sha256']),))
    return {'state_store_replay': fixture}, evidence


# Admission fixtures contain upstream proof/accumulator values, not a Python implementation of selection.
def unit_ticket_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from ticket_admission_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_TICKET_ADMISSION', path, ((path, evidence['fixture_sha256']),))
    return {'ticket_admission': fixture, 'ticket_state': fixture}, evidence


# Prepare exact published roster projections for the bounded planner's native assertions.
def unit_validator_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from validator_rotation_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_VALIDATOR_STF', path, ((path, evidence['fixture_sha256']),))
    return {'validator_rotation': fixture, 'validator_state': fixture}, evidence


# Prepare only the published entropy/time projections, keeping full Safrole execution outside this suite.
def unit_entropy_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from entropy_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_ENTROPY_STF', path, ((path, evidence['fixture_sha256']),))
    return {'entropy_transition': fixture}, evidence


# Prepare public upstream credentials with independent OpenSSL positive/old-domain verdicts.
def unit_signing_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from signing_domain_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_SIGNING_DOMAINS', path, ((path, evidence['fixture_sha256']),))
    return {'signing_domains': fixture}, evidence


# Prepare published history cases and independent output-tree commitments for native assertions.
def unit_history_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from history_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_HISTORY_STF', path, ((path, evidence['fixture_sha256']),))
    return {'history_transition': fixture}, evidence


# Prepare complete pinned authorization STF cases; the native suite executes and asserts the subsystem.
def unit_authorization_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from authorization_transition_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_AUTHORIZATION_STF', path, ((path, evidence['fixture_sha256']),))
    return {'authorization_transition': fixture}, evidence


# Describe freshly generated certificates and independent CE fixtures without committing private keys.
def unit_runtime_fixtures(certificates, original, reload):
    transport = {'RAGNAROK_TEST_CERT': certificates/'a.cert.pem',
                 'RAGNAROK_TEST_KEY': certificates/'a.key.pem'}
    integration = {'RAGNAROK_TEST_WIRES': original, 'RAGNAROK_TEST_RELOAD': reload}
    # Every referenced input is hashed and rechecked before the native process, including later siblings.
    cert_files = tuple((path, hashlib.sha256(path.read_bytes()).hexdigest()) for path in transport.values())
    wires = tuple((folder/(str(index)+'.bin'), hashlib.sha256((folder/(str(index)+'.bin')).read_bytes()).hexdigest())
                  for folder in (original, reload) for index in range(8))
    return {'quic_transport': (None, transport, cert_files), 'quic_integration': (None, integration, wires)}


# Generate gas inputs under the caller's ignored build directory from pinned submodule witnesses.
def unit_pvm_gas_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from pvm_gas_reference import prepare
    path, evidence = prepare(folder)
    return {'pvm_gas': ('RAGNAROK_PVM_GAS', path, ((path, evidence['fixture_sha256']),))}, evidence


# Generate composed stepping traces in build storage without adding checked-in binary copies.
def unit_pvm_step_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from pvm_step_reference import prepare
    path, evidence = prepare(folder)
    return {'pvm_step': ('RAGNAROK_PVM_STEP', path, ((path, evidence['fixture_sha256']),))}, evidence
