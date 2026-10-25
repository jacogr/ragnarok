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


def scenarios(compiler, checks, libraries, oracle, fixtures):
    """Freeze expected answers before building one shared native driver; retain exact request and output hashes."""
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in fixtures:
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = oracle.expected_observations()
    source = checks.folder/(oracle.FIXTURE.stem+'-requests.txt')
    source.write_text('\n'.join(requests)+'\n')
    built, binary = checks.build(compiler, ROOT/'tests/native/current_stf_reporting_scenarios_driver.nim',
        'current-stf-reporting-scenarios', crypto_library=libraries['crypto'], native_libraries=(libraries['bandersnatch'],))
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
