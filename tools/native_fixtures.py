"""Feature-owned native fixture preparation; independent oracles retain their byte contracts."""
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
    return {'block_admission': fixture}, evidence


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
    admission_fixtures, admission_evidence = unit_admission_fixture(folder)
    fixtures.update(admission_fixtures)
    disputes_fixtures, disputes_evidence = unit_disputes_fixture(folder)
    fixtures.update(disputes_fixtures)
    availability_fixtures, availability_evidence = unit_availability_fixture(folder)
    fixtures.update(availability_fixtures)
    evidence['availability'] = availability_evidence
    evidence['disputes'] = disputes_evidence
    evidence['admission'] = admission_evidence
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
