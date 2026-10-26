# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Register Fuzz / JAM's independent interface corpora outside Unit corpus discovery."""
from pathlib import Path
import hashlib
import json
from corpus_checks import run_corpus, compare_corpus, CorpusGroup
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]
# Dedicated Fuzz owns the complete source-declared plan; native observations never calculate expected maps.
CORPORA = CorpusGroup()


@CORPORA.case
def jam_fuzzer_forks_corpus(compiler, report, checks, libraries):
    """Compare independently calculated sibling whole maps through actual fuzzer imports and state queries."""
    from jam_fuzzer_forks_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('jam_fuzzer_forks', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    expected, evidence = expected_observations()
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_forks_driver.nim',
        'jam-fuzzer-forks', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1]], 'jam-fuzzer-forks-corpus', expected)
    announce('independent depth-one fuzzer sibling STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def jam_fuzzer_ancestry_corpus(compiler, report, checks, libraries):
    """Compare real reporting imports with exact independent maps and actual child-root evidence refusals."""
    from jam_fuzzer_ancestry_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_reporting', 'jam_fuzzer_ancestry', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-ancestry-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_ancestry_driver.nim',
        'jam-fuzzer-ancestry', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-ancestry-corpus', expected)
    announce('independent fuzzer reporting ancestry whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def jam_fuzzer_ancestry_retention_corpus(compiler, report, checks, libraries):
    """Compare real reporting imports with exact independent maps and actual child-root evidence refusals."""
    from jam_fuzzer_ancestry_retention_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_reporting', 'jam_fuzzer_ancestry_retention', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-ancestry-retention-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_ancestry_retention_driver.nim',
        'jam-fuzzer-ancestry-retention', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-ancestry-retention-corpus', expected)
    announce('independent fuzzer bounded ancestry retention whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def jam_fuzzer_report_forks_corpus(compiler, report, checks, libraries):
    """Compare real reporting imports with exact independent maps and actual child-root evidence refusals."""
    from jam_fuzzer_report_forks_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf', 'current_stf_reporting', 'jam_fuzzer_ancestry', 'jam_fuzzer_report_forks', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-report-forks-requests.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_report_forks_driver.nim',
        'jam-fuzzer-report-forks', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-report-forks-corpus', expected)
    announce('independent fuzzer nonempty reporting sibling whole STF maps', corpus['passed'])
    return corpus



def run_fuzzer_guest_reference(compiler, report, checks, libraries, reference, identities,
                               *, input_requests=True, profiles=None, forks=False, anchor_checks=False, headers=False):
    """Share exact-input replay builds while each source-owned corpus retains its own frozen reference and verdict."""
    from jam_fuzzer_guest_reference import replay
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in (*identities, 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    requests, expected, evidence = replay(reference, input_requests=input_requests, profiles=profiles, forks=forks, anchor_checks=anchor_checks, headers=headers)
    label = 'jam-fuzzer-'+reference.FIXTURE.stem.removeprefix('current-stf-')
    source = checks.folder/(label+'.txt')
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_guest_replay.nim',
        'jam-fuzzer-guest-replay', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], label+'-corpus', expected)
    announce(label+' independent whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def jam_fuzzer_report_guests_corpus(compiler, report, checks, libraries):
    """Compare actual fuzzer report-to-guest execution with independent complete-map STF calculations."""
    import current_stf_report_guests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_effects', 'current_stf_report_guests'))



@CORPORA.case
def jam_fuzzer_storage_effects_corpus(compiler, report, checks, libraries):
    """Compare nonempty preimage extrinsics and guest storage replacement/deletion/exception selection."""
    import current_stf_effects_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_effects',), input_requests=False)



@CORPORA.case
def jam_fuzzer_request_effects_corpus(compiler, report, checks, libraries):
    """Compare selected request creation, forgetting and checkpointed namespace versions through the fuzz backend."""
    import current_stf_request_lifecycle_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_request_lifecycle', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_preimage_effects_corpus(compiler, report, checks, libraries):
    """Compare queued provision relevance and actual canonical preimage fulfillment across guest selections."""
    import current_stf_preimage_provision_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_preimage_provision', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_transfers_corpus(compiler, report, checks, libraries):
    """Execute transfers through fuzz requests against independent complete STF maps."""
    import current_stf_transfers_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfers', 'current_stf_report_guests'))



@CORPORA.case
def jam_fuzzer_supervised_transfers_corpus(compiler, report, checks, libraries):
    """Execute supervised transfers through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_transfers_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_transfers', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_forwarded_transfers_corpus(compiler, report, checks, libraries):
    """Execute forwarded transfers through fuzz requests against independent complete STF maps."""
    import current_stf_forwarded_transfers_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_forwarded_transfers', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_transfer_pools_corpus(compiler, report, checks, libraries):
    """Execute transfer pools through fuzz requests against independent complete STF maps."""
    import current_stf_transfer_pools_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfer_pools', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_transfer_admission_corpus(compiler, report, checks, libraries):
    """Execute transfer admission through fuzz requests against independent complete STF maps."""
    import current_stf_transfer_admission_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfer_admission', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_transfer_memos_corpus(compiler, report, checks, libraries):
    """Execute transfer memos through fuzz requests against independent complete STF maps."""
    import current_stf_transfer_memos_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_transfer_memos', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_service_upgrades_corpus(compiler, report, checks, libraries):
    """Execute service upgrades through fuzz requests against independent complete STF maps."""
    import current_stf_service_upgrades_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_service_upgrades', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_supervisor_lifecycle_corpus(compiler, report, checks, libraries):
    """Execute supervisor lifecycle through fuzz requests against independent complete STF maps."""
    import current_stf_supervisor_lifecycle_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervisor_lifecycle', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_service_creation_corpus(compiler, report, checks, libraries):
    """Execute service creation through fuzz requests against independent complete STF maps."""
    import current_stf_service_creation_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_service_creation', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_service_ejection_corpus(compiler, report, checks, libraries):
    """Execute service ejection through fuzz requests against independent complete STF maps."""
    import current_stf_service_ejection_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_service_ejection', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_manager_handoff_corpus(compiler, report, checks, libraries):
    """Execute manager handoff through fuzz requests against independent complete STF maps."""
    import current_stf_manager_handoff_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_manager_handoff', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_authorization_assign_corpus(compiler, report, checks, libraries):
    """Execute authorization assign through fuzz requests against independent complete STF maps."""
    import current_stf_authorization_assign_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=size) for size in json.loads(reference.FIXTURE.read_text())['max_service_code_sizes']]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_authorization_assign', 'current_stf_transfers'), profiles=profiles)



@CORPORA.case
def jam_fuzzer_role_precedence_corpus(compiler, report, checks, libraries):
    """Execute role precedence through fuzz requests against independent complete STF maps."""
    import current_stf_role_precedence_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=size) for size in [json.loads(reference.FIXTURE.read_text())['max_service_code_size']]*len(reference.PROFILES)]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_role_precedence', 'current_stf_transfers'), profiles=profiles)



@CORPORA.case
def jam_fuzzer_validator_designation_corpus(compiler, report, checks, libraries):
    """Execute validator designation through fuzz requests against independent complete STF maps."""
    import current_stf_validator_designation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=size) for size in [json.loads(reference.FIXTURE.read_text())['max_service_code_size']]*len(reference.PROFILES)]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_validator_designation', 'current_stf_transfers'), profiles=profiles)



@CORPORA.case
def jam_fuzzer_bless_allowances_corpus(compiler, report, checks, libraries):
    """Execute bless allowances through fuzz requests against independent complete STF maps."""
    import current_stf_bless_allowances_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_bless_allowances', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_allowance_revocation_corpus(compiler, report, checks, libraries):
    """Execute allowance revocation through fuzz requests against independent complete STF maps."""
    import current_stf_allowance_revocation_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_allowance_revocation', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_allowance_eligibility_corpus(compiler, report, checks, libraries):
    """Execute allowance eligibility through fuzz requests against independent complete STF maps."""
    import current_stf_allowance_eligibility_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_allowance_eligibility', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_supervised_storage_corpus(compiler, report, checks, libraries):
    """Execute supervised storage through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_storage_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_storage', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_supervised_requests_corpus(compiler, report, checks, libraries):
    """Execute supervised requests through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_requests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_requests', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_supervised_upgrades_corpus(compiler, report, checks, libraries):
    """Execute supervised upgrades through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_upgrades_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_upgrades', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_supervised_conflicts_corpus(compiler, report, checks, libraries):
    """Execute supervised conflicts through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_conflicts_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_conflicts', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_supervised_handoff_corpus(compiler, report, checks, libraries):
    """Execute supervised handoff through fuzz requests against independent complete STF maps."""
    import current_stf_supervised_handoff_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_supervised_handoff', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_reserved_creation_corpus(compiler, report, checks, libraries):
    """Execute reserved creation through fuzz requests against independent complete STF maps."""
    import current_stf_reserved_creation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_reserved_creation', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))



@CORPORA.case
def jam_fuzzer_child_readiness_corpus(compiler, report, checks, libraries):
    """Execute child readiness through fuzz requests against independent complete STF maps."""
    import current_stf_child_readiness_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_child_readiness', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_child_retirement_corpus(compiler, report, checks, libraries):
    """Execute child retirement through fuzz requests against independent complete STF maps."""
    import current_stf_child_retirement_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_child_retirement', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))



@CORPORA.case
def jam_fuzzer_child_recreation_corpus(compiler, report, checks, libraries):
    """Execute child recreation through fuzz requests against independent complete STF maps."""
    import current_stf_child_recreation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_child_recreation', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))



@CORPORA.case
def jam_fuzzer_incarnation_authority_corpus(compiler, report, checks, libraries):
    """Execute incarnation authority through fuzz requests against independent complete STF maps."""
    import current_stf_incarnation_authority_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_incarnation_authority', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_foreign_creation_corpus(compiler, report, checks, libraries):
    """Execute foreign creation through fuzz requests against independent complete STF maps."""
    import current_stf_foreign_creation_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_foreign_creation', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))



@CORPORA.case
def jam_fuzzer_foreign_transfers_corpus(compiler, report, checks, libraries):
    """Execute foreign transfers through fuzz requests against independent complete STF maps."""
    import current_stf_foreign_transfers_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_foreign_transfers', 'current_stf_transfers'),
                                     profiles=[host_parameters(deposits=(7, 1, 100))] * len(reference.PROFILES))



@CORPORA.case
def jam_fuzzer_queued_incarnation_corpus(compiler, report, checks, libraries):
    """Execute queued incarnation through fuzz requests against independent complete STF maps."""
    import current_stf_queued_incarnation_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_queued_incarnation', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_dependency_waves_corpus(compiler, report, checks, libraries):
    """Execute dependency waves through fuzz requests against independent complete STF maps."""
    import current_stf_dependency_waves_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_effects', 'current_stf_report_guests', 'current_stf_dependency_waves'))



@CORPORA.case
def jam_fuzzer_budget_retention_corpus(compiler, report, checks, libraries):
    """Execute budget retention through fuzz requests against independent complete STF maps."""
    import current_stf_budget_retention_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_budget_retention', 'current_stf_dependency_waves'))



@CORPORA.case
def jam_fuzzer_gas_exits_corpus(compiler, report, checks, libraries):
    """Execute gas exits through fuzz requests against independent complete STF maps."""
    import current_stf_gas_exits_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_gas_exits', 'current_stf_report_guests'))



@CORPORA.case
def jam_fuzzer_late_code_corpus(compiler, report, checks, libraries):
    """Execute late code through fuzz requests against independent complete STF maps."""
    import current_stf_late_code_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_late_code', 'current_stf_report_guests'))



@CORPORA.case
def jam_fuzzer_epoch_drain_corpus(compiler, report, checks, libraries):
    """Execute epoch drain through fuzz requests against independent complete STF maps."""
    import current_stf_epoch_drain_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_epoch_drain', 'current_stf_dependency_waves'))



@CORPORA.case
def jam_fuzzer_ready_expiry_corpus(compiler, report, checks, libraries):
    """Execute ready expiry through fuzz requests against independent complete STF maps."""
    import current_stf_ready_expiry_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_ready_expiry', 'current_stf_epoch_drain'))



@CORPORA.case
def jam_fuzzer_epoch_lifecycle_corpus(compiler, report, checks, libraries):
    """Execute epoch lifecycle through fuzz requests against independent complete STF maps."""
    import current_stf_epoch_lifecycle_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_epoch_lifecycle', 'current_stf_transfers'))



@CORPORA.case
def jam_fuzzer_epoch_composition_corpus(compiler, report, checks, libraries):
    """Execute epoch composition through fuzz requests against independent complete STF maps."""
    import current_stf_epoch_composition_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    profiles = [host_parameters(code_limit=4096 if 107 <= mode <= 122 and mode != 112 else 512,
                                deposits=(7, 1, 100) if mode in range(123, 131) or mode in range(141, 155) else (0, 0, 0))
                for _, _, mode in reference.CASES]
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_epoch_composition', 'current_stf_transfers'), profiles=profiles)



@CORPORA.case
def jam_fuzzer_guest_forks_corpus(compiler, report, checks, libraries):
    """Compare guest-bearing siblings and original-last continuation with independent complete maps."""
    import jam_fuzzer_guest_forks_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
                                     ('current_stf_report_guests', 'jam_fuzzer_guest_forks'), forks=True)



@CORPORA.case
def jam_fuzzer_parameter_aging_corpus(compiler, report, checks, libraries):
    """Use authoritative GP lookup age for genuine reporting, strict aging and contradictory-policy controls."""
    import jam_fuzzer_parameter_aging_oracle as reference
    from jam_fuzzer_guest_reference import host_parameters
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_preimage_aging', 'jam_fuzzer_parameter_aging'),
        profiles=[host_parameters(lookup_age=reference.LOOKUP_AGE)] * len(reference.source.PROFILES),
        anchor_checks=True)



@CORPORA.case
def jam_fuzzer_seed_guests_corpus(compiler, report, checks, libraries):
    """Execute exact genesis-like seed pairs while retaining both GP chronology checks and production isolation."""
    import jam_fuzzer_seed_guests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_effects', 'jam_fuzzer_seed_guests'), headers=True)



@CORPORA.case
def jam_fuzzer_checkpoint_guests_corpus(compiler, report, checks, libraries):
    """Resume independently authored whole-map guest checkpoints with exact minimal ancestry evidence."""
    import jam_fuzzer_checkpoint_guests_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_report_guests', 'jam_fuzzer_checkpoint_guests'), headers=True)



@CORPORA.case
def jam_fuzzer_account_forks_corpus(compiler, report, checks, libraries):
    """Compare independently calculated funded-account and incarnation siblings through actual fuzz imports."""
    import jam_fuzzer_account_forks_oracle as reference
    from jam_fuzzer_effect_forks_reference import profiles
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        tuple('current_stf_'+family for family in reference.FAMILIES)+('jam_fuzzer_account_forks',),
        forks=True, profiles=profiles(reference.FAMILIES))



@CORPORA.case
def jam_fuzzer_privileged_forks_corpus(compiler, report, checks, libraries):
    """Execute independent privileged siblings and require exact original-last namespace effects."""
    import jam_fuzzer_privileged_forks_oracle as reference
    from jam_fuzzer_effect_forks_reference import profiles
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        tuple('current_stf_'+family for family in reference.FAMILIES)+('jam_fuzzer_privileged_forks',),
        forks=True, profiles=profiles(reference.FAMILIES))



@CORPORA.case
def jam_fuzzer_supervised_forks_corpus(compiler, report, checks, libraries):
    """Execute independent supervised siblings and require exact original-last namespace effects."""
    import jam_fuzzer_supervised_forks_oracle as reference
    from jam_fuzzer_effect_forks_reference import profiles
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        tuple('current_stf_'+family for family in reference.FAMILIES)+('jam_fuzzer_supervised_forks',),
        forks=True, profiles=profiles(reference.FAMILIES))



@CORPORA.case
def jam_fuzzer_deferred_forks_corpus(compiler, report, checks, libraries):
    """Execute independent deferred siblings and require exact original-last namespace effects."""
    import jam_fuzzer_deferred_forks_oracle as reference
    from jam_fuzzer_effect_forks_reference import profiles
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        tuple('current_stf_'+family for family in reference.FAMILIES)+('jam_fuzzer_deferred_forks',),
        forks=True, profiles=profiles(reference.FAMILIES))



@CORPORA.case
def jam_fuzzer_epoch_effect_forks_corpus(compiler, report, checks, libraries):
    """Execute independent epoch siblings and require exact original-last namespace effects."""
    import jam_fuzzer_epoch_effect_forks_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        tuple('current_stf_'+family for family in reference.FAMILIES)+('jam_fuzzer_epoch_effect_forks',),
        forks=True, profiles=reference.host_profiles())



@CORPORA.case
def jam_fuzzer_fork_capacity_corpus(compiler, report, checks, libraries):
    """Compare nine full guest siblings, eight-state eviction and direct-extension retirement against independent maps."""
    import jam_fuzzer_fork_capacity_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_guest_ring_input', 'jam_fuzzer_fork_capacity', 'jam_fuzzer_full_guests'),
        forks=True, headers=True, profiles=[full.parameters()]*len(reference.guests.MODES))



@CORPORA.case
def jam_fuzzer_full_ancestry_corpus(compiler, report, checks, libraries):
    """Execute actual full-profile checkpoint ancestry and retained seed queries beyond both history ceilings."""
    import jam_fuzzer_full_ancestry_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_guest_ring_input', 'jam_fuzzer_full_ancestry', 'jam_fuzzer_full_guests'),
        profiles=[full.parameters()], headers=True)



@CORPORA.case
def jam_fuzzer_full_contest_corpus(compiler, report, checks, libraries):
    """Require full600-ticket eviction and typed atomic refusals with every complete retained map unchanged."""
    import jam_fuzzer_full_contest_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_ticket_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_contest'),
        profiles=[full.parameters()]*2)



@CORPORA.case
def jam_fuzzer_full_epochs_corpus(compiler, report, checks, libraries):
    """Compare guest-bearing full epoch markers, skipped tails and1023-to1020 population rotation."""
    import jam_fuzzer_full_epochs_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_epoch_ring_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_epochs',
         'jam_fuzzer_full_guests', 'jam_fuzzer_full_profile'),
        profiles=[full.parameters()]*len(reference.SLOTS))



@CORPORA.case
def jam_fuzzer_full_epoch_capacity_corpus(compiler, report, checks, libraries):
    """Compare nine epoch-crossing guest siblings, original-last retention and canonical group retirement."""
    import jam_fuzzer_full_epoch_capacity_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_population_ring_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_epoch_capacity',
         'jam_fuzzer_full_epoch_guests'), forks=True, headers=True, profiles=[full.parameters()]*len(reference.MODES))



@CORPORA.case
def jam_fuzzer_full_epoch_checkpoints_corpus(compiler, report, checks, libraries):
    """Compare honest guest checkpoint restarts through both physical population rotations."""
    import jam_fuzzer_full_epoch_checkpoints_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_population_ring_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_epoch_checkpoints',
         'jam_fuzzer_full_epoch_guests'), headers=True, profiles=[full.parameters()]*len(reference.MODES))



@CORPORA.case
def jam_fuzzer_full_epoch_forks_corpus(compiler, report, checks, libraries):
    """Compare epoch-crossing siblings, original-last state and canonical population rotation over real guest maps."""
    import jam_fuzzer_full_epoch_forks_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_population_ring_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_epoch_forks',
         'jam_fuzzer_full_epoch_guests'), forks=True, headers=True, profiles=[full.parameters()]*len(reference.MODES))



@CORPORA.case
def jam_fuzzer_full_epoch_guests_corpus(compiler, report, checks, libraries):
    """Compare guest namespaces, MMR and statistics across offender filtering and two population rotations."""
    import jam_fuzzer_full_epoch_guests_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_population_ring_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_epoch_guests',
         'jam_fuzzer_full_population', 'jam_fuzzer_full_guests'), profiles=[full.parameters()]*len(reference.MODES))



@CORPORA.case
def jam_fuzzer_full_guests_corpus(compiler, report, checks, libraries):
    """Execute distinct full-population admission, high-core quorums and nonempty guest sibling maps."""
    import jam_fuzzer_full_guests_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_report_guests', 'jam_full_guest_ring_input', 'jam_fuzzer_full_guests',
         'jam_fuzzer_full_profile'), forks=True, profiles=[full.parameters()]*len(reference.MODES))



@CORPORA.case
def jam_fuzzer_full_offender_guests_corpus(compiler, report, checks, libraries):
    """Compare same-block punished-guarantor refusal, valid alternate credentials and prior-active guest availability."""
    import jam_fuzzer_full_offender_guests_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_guest_ring_input', 'jam_fuzzer_full_offender_guests', 'jam_fuzzer_full_pending_disputes', 'jam_fuzzer_full_guests'),
        profiles=[full.parameters()]*len(reference.MODES))



@CORPORA.case
def jam_fuzzer_full_offenders_corpus(compiler, report, checks, libraries):
    """Execute full-roster culprit/fault evidence, cross-section markers and typed atomic refusals."""
    import jam_fuzzer_full_offenders_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_guest_ring_input', 'jam_fuzzer_full_offenders', 'jam_fuzzer_full_guests'),
        profiles=[full.parameters()])



@CORPORA.case
def jam_fuzzer_full_pending_disputes_corpus(compiler, report, checks, libraries):
    """Compare real low/high-core report cancellation, retained assignments, report-hash identity and late-fault rollback."""
    import jam_fuzzer_full_pending_disputes_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_guest_ring_input', 'jam_fuzzer_full_pending_disputes', 'jam_fuzzer_full_guests', 'jam_fuzzer_full_verdicts'),
        profiles=[full.parameters()]*2)



@CORPORA.case
def jam_fuzzer_full_population_corpus(compiler, report, checks, libraries):
    """Compare full offender nulling, delayed1020-member activation, multi-epoch skips and exact marker refusals."""
    import jam_fuzzer_full_population_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_population_ring_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_population', 'jam_fuzzer_full_offenders'),
        profiles=[full.parameters()]*len(reference.PLANS))



@CORPORA.case
def jam_fuzzer_full_profile_corpus(compiler, report, checks, libraries):
    """Execute full341-core/1023-validator/600-slot complete maps under every pinned GP parameter."""
    import jam_fuzzer_full_profile_oracle as reference
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_transfers', 'jam_full_ring_input', 'jam_fuzzer_full_profile'),
        profiles=[reference.parameters()]*2)



@CORPORA.case
def jam_fuzzer_full_sealing_corpus(compiler, report, checks, libraries):
    """Compare full600-entry winner markers, ticket/fallback credentials and exact marker refusals over epoch crossings."""
    import jam_fuzzer_full_sealing_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_ticket_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_contest', 'jam_fuzzer_full_sealing'),
        profiles=[full.parameters()]*len(reference.PLANS))



@CORPORA.case
def jam_fuzzer_full_tickets_corpus(compiler, report, checks, libraries):
    """Execute full16-ticket blocks against independent complete maps and author-specific statistics."""
    import jam_fuzzer_full_tickets_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_ticket_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_tickets'),
        profiles=[full.parameters()]*2)



@CORPORA.case
def jam_fuzzer_full_verdict_availability_corpus(compiler, report, checks, libraries):
    """Compare cancellation before assurance bits, exact late rollback and surviving-report guest effects."""
    import jam_fuzzer_full_verdict_availability_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_guest_ring_input', 'jam_fuzzer_full_verdict_availability', 'jam_fuzzer_full_pending_disputes', 'jam_fuzzer_full_guests'),
        profiles=[full.parameters()]*len(reference.MODES))



@CORPORA.case
def jam_fuzzer_full_verdict_populations_corpus(compiler, report, checks, libraries):
    """Compare original-parent683/current681/previous683 verdicts, NULL-slot quorums and evidence membership expiry."""
    import jam_fuzzer_full_verdict_populations_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_population_ring_input', 'jam_full_guest_ring_input', 'jam_fuzzer_full_verdict_populations',
         'jam_fuzzer_full_population', 'jam_fuzzer_full_verdicts'), profiles=[full.parameters()])



@CORPORA.case
def jam_fuzzer_full_verdicts_corpus(compiler, report, checks, libraries):
    """Compare three full683-vote verdicts, opposing faults and exact atomic GP refusal maps."""
    import jam_fuzzer_full_verdicts_oracle as reference
    import jam_fuzzer_full_profile_oracle as full
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('jam_full_guest_ring_input', 'jam_fuzzer_full_verdicts', 'jam_fuzzer_full_guests'),
        profiles=[full.parameters()])



@CORPORA.case
def jam_fuzzer_transfer_forks_corpus(compiler, report, checks, libraries):
    """Compare independent actual transfer-bearing siblings with exact original-last state and continuation."""
    import jam_fuzzer_transfer_forks_oracle as reference
    from jam_fuzzer_effect_forks_reference import profiles
    return run_fuzzer_guest_reference(compiler, report, checks, libraries, reference,
        ('current_stf_transfers', 'current_stf_supervised_transfers', 'current_stf_forwarded_transfers',
         'current_stf_transfer_pools', 'current_stf_transfer_admission', 'current_stf_transfer_memos',
         'jam_fuzzer_transfer_forks'), forks=True, profiles=profiles(reference.FAMILIES))



@CORPORA.case
def jam_fuzzer_stf_corpus(compiler, report, checks, libraries):
    """Compare actual fuzzer requests and whole-state replies with frozen independent STF maps."""
    from current_stf_oracle import expected_observations, verify_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    # Freeze complete independent pre/block/post expectations before the backend is built or run.
    expected = expected_observations()
    evidence = verify_observations(expected)
    for identity in ('current_stf', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_stf_driver.nim',
        'jam-fuzzer-stf', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, **evidence,
                  scope='native fuzzer requests; two linear current-profile chains; whole GetState maps')
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1]], 'jam-fuzzer-stf-corpus', expected)
    announce('independent whole-map JAM fuzzer STF backend', corpus['passed'])
    return corpus



@CORPORA.case
def jam_fuzzer_epoch_forks_corpus(compiler, report, checks, libraries):
    """Execute epoch rotation, cutoff markers and real RingVRF admission against independent complete maps."""
    from jam_fuzzer_epoch_forks_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for identity in ('current_stf_epoch', 'jam_fuzzer_epoch_forks', 'state_report'):
        for path, digest in FIXTURE_CONTRACTS[identity][2]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    # Frozen Ring/KZG witnesses are input data; every score, Thin credential and successor map is independently calculated.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-epoch-forks-proofs.txt'
    source.write_text('\n'.join(requests)+'\n')
    compiled, binary = checks.build(compiler, ROOT/'tests/native/jam_fuzzer_epoch_forks_driver.nim',
        'jam-fuzzer-epoch-forks', crypto_library=libraries['crypto'],
        native_libraries=(libraries['bandersnatch'],), quic_library=libraries['quic'])
    corpus = dict(build=compiled, passed=False, requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  **evidence)
    compare_corpus(corpus, checks.command,
                   [binary, FIXTURE_CONTRACTS['state_report'][1], source], 'jam-fuzzer-epoch-forks-corpus', expected)
    announce('independent epoch/ticket whole STF maps', corpus['passed'])
    return corpus



@CORPORA.case
def jam_fuzzer_wire_corpus(compiler, report, checks, libraries):
    """Compare pinned known JAM session bytes and independent complete opaque maps under explicit current structural domains."""
    from jam_fuzzer_wire_oracle import expected_observations
    from native_fixture_contracts import FIXTURE_CONTRACTS
    for path, digest in FIXTURE_CONTRACTS['jam_fuzzer_wire'][2]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest # Freeze the exact expected observations before native execution.
    requests, expected, evidence = expected_observations()
    source = checks.folder/'jam-fuzzer-wire-requests.txt'
    return run_corpus(checks.build,checks.command,compiler,
        ROOT/'tests/native/jam_fuzzer_wire_driver.nim','jam-fuzzer-wire',source,requests,expected,
        'jam-fuzzer-wire-corpus',metadata=dict(**evidence,
            reference='pinned known JAM historical message bytes; independent current structural framing and complete opaque maps; no STF campaign execution'),
        crypto_library=libraries['crypto'])

