# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Source-owned independent reporting scenario qualification through the actual candidate/import pipeline."""
import hashlib
from pathlib import Path
from corpus_checks import CorpusGroup
from reporting_comparison import compare_chains
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]
CORPORA = CorpusGroup(order=25)


def scenarios(compiler, checks, libraries, oracle, fixtures, *, defines=()):
    """Freeze expected answers before building one shared native driver; retain exact request and output hashes."""
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in fixtures:
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = oracle.expected_observations()
    source = checks.folder/(oracle.FIXTURE.stem+'-requests.txt')
    source.write_text('\n'.join(requests)+'\n')
    built, binary = checks.build(compiler, ROOT/'tests/native/current_stf_reporting_scenarios_driver.nim',
        'current-stf-reporting-scenarios'+('-rotation-designation' if 'rotationDesignations' in defines else '-rotation-hosts' if defines else ''), defines=defines, crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
    result = dict(build=built, passed=False, **evidence, requests=len(requests),
        requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        reference='GP mathematical Thin, independent Ed25519 signatures and complete-map equations')
    compare_chains(result, checks.command, binary, FIXTURE_CONTRACTS['state_report'][1], source,
                   requests, expected, evidence['chains'])
    announce(oracle.FIXTURE.stem+' independent signed complete-map scenarios', result['passed'])
    return result


@CORPORA.case
def current_stf_offender_reporting_corpus(compiler, report, checks, libraries):
    """Qualify assurance-before-rotation, Phi guarantor exclusion, cancellation and delayed nulling together."""
    import current_stf_offender_reporting_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_offender_reporting', 'state_report'))


@CORPORA.case
def current_stf_rotation_transfers_corpus(compiler, report, checks, libraries):
    """Qualify direct/deferred balance pools, literal memo delivery and refusal/gas boundaries across rotation."""
    import current_stf_rotation_transfers_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_transfers',
         'current_stf_transfer_pools', 'current_stf_transfer_admission', 'current_stf_transfer_memos',
         'current_stf_rotation_transfers', 'state_report'), defines=('rotationHosts',))


@CORPORA.case
def current_stf_rotation_designation_corpus(compiler, report, checks, libraries):
    """Qualify real designation, simultaneous delegation handoff and delayed promotion through four epochs."""
    import current_stf_rotation_designation_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_validator_designation',
         'current_stf_rotation_designation', 'state_report'), defines=oracle.NATIVE_DEFINES)


@CORPORA.case
def current_stf_rotation_privileges_corpus(compiler, report, checks, libraries):
    """Qualify original-role queue/manager selection and delayed allowance scheduling across growth/shrinkage."""
    import current_stf_rotation_privileges_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_bless_allowances',
         'current_stf_authorization_assign', 'current_stf_manager_handoff', 'current_stf_role_precedence', 'current_stf_rotation_privileges', 'state_report'),
        defines=('rotationHosts',))


@CORPORA.case
def current_stf_population_guests_corpus(compiler, report, checks, libraries):
    """Qualify real report-triggered writes, rollback and checkpoints across changing roster populations."""
    import current_stf_population_guests_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_effects', 'current_stf_population_guests', 'state_report'))


@CORPORA.case
def current_stf_ticket_reporting_corpus(compiler, report, checks, libraries):
    """Qualify ticket winners/fallback sealing alongside real reports and later population growth."""
    import current_stf_ticket_reporting_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_ticket_reporting', 'state_report'))


@CORPORA.case
def current_stf_population_waves_corpus(compiler, report, checks, libraries):
    """Qualify deferred dependency waves and actual-gas continuation across population growth/shrinkage."""
    import current_stf_population_waves_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_effects', 'current_stf_dependency_waves', 'current_stf_population_waves', 'state_report'))


@CORPORA.case
def current_stf_population_gas_corpus(compiler, report, checks, libraries):
    """Qualify exact-residual deferred retention and pooled guest exits across changing populations."""
    import current_stf_population_gas_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_effects', 'current_stf_dependency_waves', 'current_stf_gas_exits', 'current_stf_budget_retention', 'current_stf_population_gas', 'state_report'))


@CORPORA.case
def current_stf_population_anchors_corpus(compiler, report, checks, libraries):
    """Qualify exact lookup-age bounds and authenticated tuple provenance after population changes."""
    import current_stf_population_anchors_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_epoch', 'current_stf_population', 'current_stf_population_reporting', 'current_stf_population_anchors', 'state_report'))


@CORPORA.case
def current_stf_population_restart_corpus(compiler, report, checks, libraries):
    """Qualify complete checkpoint continuation with independently trusted roots across dynamic-roster state families."""
    import current_stf_population_restart_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_effects', 'current_stf_epoch', 'current_stf_offender_reporting',
         'current_stf_population', 'current_stf_population_anchors', 'current_stf_population_gas',
         'current_stf_population_guests', 'current_stf_population_restart', 'current_stf_population_waves',
         'current_stf_ticket_reporting', 'state_report'))


@CORPORA.case
def current_stf_population_trace_corpus(compiler, report, checks, libraries):
    """Qualify authenticated full TraceStep imports and exact wrong-map/seal refusals across dynamic rosters."""
    import current_stf_population_trace_oracle as oracle
    return scenarios(compiler, checks, libraries, oracle,
        ('current_stf', 'current_stf_effects', 'current_stf_epoch', 'current_stf_offender_reporting',
         'current_stf_population', 'current_stf_population_anchors', 'current_stf_population_gas',
         'current_stf_population_guests', 'current_stf_population_restart', 'current_stf_population_trace',
         'current_stf_population_waves', 'current_stf_ticket_reporting', 'state_report'))


@CORPORA.case
def current_stf_population_command_corpus(compiler, report, checks, libraries):
    """Qualify portable configured operator bundles through actual public offline commands and exact refusals."""
    import json
    import current_stf_population_command_oracle as oracle
    from native_fixture_contracts import FIXTURE_CONTRACTS
    from reporting_operator import materialize,compare_jobs
    from corpus_checks import compare_corpus
    for identity in ('current_stf_population_command','current_stf_population_trace','current_stf_trace_command'):
        for path,digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest()==digest
    jobs,expected,evidence=oracle.expected_observations()
    folder=checks.folder/'population operator bundles'
    commands,manifest,paths=materialize(folder,jobs,expected)
    # Materialization must preserve every independently frozen input before any compiler/native command can observe it.
    for ordinal,job in enumerate(evidence['jobs']):
        prefix='case-'+str(ordinal).zfill(4)+'/'
        assert manifest['files'][prefix+'chain.json']==job['config_sha256']
        assert manifest['files'][prefix+'genesis.bin']==job['genesis_sha256']
        assert [manifest['files'][prefix+'step-'+str(i).zfill(4)+'.bin'] for i in range(len(job['steps_sha256']))]==job['steps_sha256']
    built,binary=checks.build(compiler,ROOT/'tests/native/current_stf_trace_command_driver.nim',
        'current-stf-trace-command',crypto_library=libraries['crypto'],native_libraries=(libraries['bandersnatch'],),quic_library=libraries['quic'])
    result=dict(build=built,passed=False,**evidence,requests=len(jobs),
        bundle_manifest_sha256=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
        reference='independent complete configured Genesis/TraceStep inputs; actual public offline command; no external-client observations')
    compare_jobs(result,checks.command,binary,checks.folder/'population-operator-policy.txt',commands,expected,paths)
    announce('changing-roster portable operator bundles and offline commands',result['passed'])
    return result
