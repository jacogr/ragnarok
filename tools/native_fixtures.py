"""Feature-owned native fixture preparation; independent oracles retain their byte contracts."""
import sys
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


# Prepare independent guarantor assignment inputs and retain the published fixture hash.
def unit_guarantors_fixture(folder):
    sys.path.insert(0, str(ROOT/'tests'))
    from guarantor_fixtures import prepare
    path, evidence = prepare(folder)
    fixture = ('RAGNAROK_GUARANTORS', path, ((path, evidence['fixture_sha256']),))
    return {'guarantor_assignments': fixture}, evidence


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
    guarantors_fixtures, guarantors_evidence = unit_guarantors_fixture(folder)
    fixtures.update(guarantors_fixtures)
    evidence['guarantors'] = guarantors_evidence
    evidence['availability'] = availability_evidence
    evidence['disputes'] = disputes_evidence
    evidence['admission'] = admission_evidence
    evidence['commitment'] = commitment_evidence
    evidence['transition'] = transition_evidence
    evidence['authentication'] = authentication_evidence
    evidence['markers'] = markers_evidence
    return fixtures, evidence
