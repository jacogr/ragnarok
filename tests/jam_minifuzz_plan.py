# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Source-owned minifuzz references declare immutable fixture coverage before any oracle or target runs."""
from dataclasses import dataclass
import hashlib
import json
from native_fixture_contracts import FIXTURE_CONTRACTS
from jam_fuzzer_stream_recovery import required_controls as recovery_controls
from jam_fuzzer_fork_retention import required_controls as fork_controls

CONTROL_FIELDS = ('local_missing_evidence','stream_recoveries','fork_evictions')


@dataclass(frozen=True)
class Reference:
    """One named fixture owner retains its lazy builder and separately declared control requirements."""
    build: object
    controls: object


_REFERENCES = {}


def reference(*, controls=None):
    """Register a source-owned fixture identity from its builder name without executing the builder."""
    def register(function):
        """Refuse duplicate or undeclared owners during metadata-only discovery."""
        identity = function.__name__
        assert identity in FIXTURE_CONTRACTS and identity not in _REFERENCES
        _REFERENCES[identity] = Reference(function,controls)
        return function
    return register


def expectations():
    """Read pinned fixture budgets and hashes independently of generated jobs, observations or target replies."""
    rows = []
    # Independent owners are discovered lexically; none of their oracle builders runs during this phase.
    for identity,entry in sorted(_REFERENCES.items()):
        _,target,members = FIXTURE_CONTRACTS[identity]
        # Validate every declared member before deriving budgets from its pinned metadata.
        for path,pin in members: assert hashlib.sha256(path.read_bytes()).hexdigest() == pin
        frozen = json.loads(target.read_text());assert isinstance(frozen,dict)
        roots = frozen.get('successor_roots',())
        sessions = frozen.get('sessions',frozen.get('chains',len(roots)))
        imports = frozen.get('transitions',sum(len(chain) for chain in roots))
        assert type(sessions) is int and sessions > 0 and type(imports) is int and imports > 0
        siblings = frozen.get('sibling_imports',frozen.get('nonempty_guest_siblings',0))
        assert type(siblings) is int and siblings >= 0
        # Multi-variant original-last publication itself occupies one position in the declared window.
        if 'fork_capacity' in frozen:
            assert siblings % sessions == 0
            siblings = sessions*min(siblings//sessions,frozen['fork_capacity']-1)
        controls = {field:0 for field in CONTROL_FIELDS}
        # Optional local-control owners declare their budgets separately from generated job tags.
        if entry.controls is not None:
            required = entry.controls()
            assert set(required) <= set(controls)
            controls.update(required)
        assert all(type(value) is int and value >= 0 for value in controls.values())
        rows.append(dict(reference=identity,fixture_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                         expected_sha256=frozen.get('expected_sha256'),sessions=sessions,signed_imports=imports,
                         exchanges=4*sessions+2*imports+siblings,controls=controls))
    assert rows
    return rows


def prepare():
    """Build each declared reference once and reject omitted steps or local controls before opening a target."""
    from nimony_fuzz_guests import session_evidence
    from jam_minifuzz_trace import retained_sibling_queries
    declared = expectations();jobs,proofs = [],[]
    for expected in declared:
        identity = expected['reference']
        selected,proof = _REFERENCES[identity].build(identity)
        assert len(selected) == expected['sessions']
        assert sum(len(job['steps']) for job in selected) == expected['signed_imports']
        assert sum(4+2*len(job['steps'])+retained_sibling_queries(job) for job in selected) == expected['exchanges']
        assert proof['reference'] == identity and proof['fixture_sha256'] == expected['fixture_sha256']
        # The legacy immediate-guest fixture retains per-case pins; aggregate-pinned streams compare exactly here.
        if expected['expected_sha256'] is not None: assert proof['expected_sha256'] == expected['expected_sha256']
        observed = session_evidence(selected,[proof])
        # Dropping a control binding cannot shrink the independently declared work.
        for field in CONTROL_FIELDS:
            assert observed['expected_'+field] == expected['controls'][field]
        jobs.extend(selected);proofs.append(proof)
    return jobs,session_evidence(jobs,proofs)


def selected(source, identity, profiles=None, **options):
    """Use the existing independent session adapter; builders retain explicit geometry and original profiles."""
    from nimony_fuzz_guests import reference_sessions
    return reference_sessions(source,identity,profiles,**options)


@reference()
def current_stf_report_guests(identity):
    """Retain the original immediate guest family with its explicit default profile."""
    import current_stf_report_guests_oracle as source
    return selected(source,identity)


@reference()
def jam_fuzzer_account_forks(identity):
    """Preserve account/incarnation sibling families and every source-specific host profile."""
    import jam_fuzzer_account_forks_oracle as source
    from jam_fuzzer_effect_forks_reference import profiles
    return selected(source,identity,profiles(source.FAMILIES))


@reference()
def jam_fuzzer_checkpoint_guests(identity):
    """Retain every separately initialized original Tiny checkpoint session."""
    import jam_fuzzer_checkpoint_guests_oracle as source
    return selected(source,identity)


@reference()
def jam_fuzzer_deferred_forks(identity):
    """Preserve deferred guest effects and their original deposit/code profiles."""
    import jam_fuzzer_deferred_forks_oracle as source
    from jam_fuzzer_effect_forks_reference import profiles
    return selected(source,identity,profiles(source.FAMILIES))


@reference()
def jam_fuzzer_epoch_effect_forks(identity):
    """Retain epoch marker extents and explicit mixed host profiles."""
    import jam_fuzzer_epoch_effect_forks_oracle as source
    return selected(source,identity,source.host_profiles())


@reference(controls=fork_controls)
def jam_fuzzer_fork_capacity(identity):
    """Bind the nine-variant whole maps to independently required eviction/retirement observations."""
    import jam_fuzzer_fork_capacity_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    from jam_fuzzer_fork_retention import bind
    jobs,proof = selected(source,identity,[parameters()]*len(source.guests.MODES),spec='full',fork_capacity=source.CAPACITY)
    # Each guest chain owns both an eviction and a later-retirement observation.
    for job in jobs: bind(job)
    return jobs,proof


@reference(controls=recovery_controls)
def jam_fuzzer_full_ancestry(identity):
    """Bind long checkpoint descendants to independently required local-evidence and recovery controls."""
    import jam_fuzzer_full_ancestry_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    from jam_fuzzer_stream_recovery import bind
    jobs,proof = selected(source,identity,[parameters()],spec='full',local_cases=[source.local_evidence_cases()])
    assert len(jobs) == 1
    bind(jobs[0])
    return jobs,proof


@reference()
def jam_fuzzer_full_contest(identity):
    """Require saturated replacement and every signed non-retained/duplicate Error with exact unchanged maps."""
    import jam_fuzzer_full_contest_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*2,spec='full')


@reference()
def jam_fuzzer_full_epochs(identity):
    """Preserve full population changes and complete variable epoch-marker traces."""
    import jam_fuzzer_full_epochs_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.SLOTS),spec='full')


@reference()
def jam_fuzzer_full_epoch_forks(identity):
    """Require different consensus epoch outcomes from the same genuine guest checkpoint."""
    import jam_fuzzer_full_epoch_forks_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.MODES),spec='full')


@reference()
def jam_fuzzer_full_epoch_guests(identity):
    """Require genuine guest effects through offender filtering and physical population rotation."""
    import jam_fuzzer_full_epoch_guests_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.MODES),spec='full')


@reference()
def jam_fuzzer_full_guests(identity):
    """Preserve distinct full-population guarantees, quorums and all guest outcomes."""
    import jam_fuzzer_full_guests_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.MODES),spec='full')


@reference()
def jam_fuzzer_full_offender_guests(identity):
    """Require newly offending guarantor rollback and genuine prior-active assurance/guest effects in every mode."""
    import jam_fuzzer_full_offender_guests_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.MODES),spec='full')


@reference()
def jam_fuzzer_full_offenders(identity):
    """Require independently calculated full-population evidence and all exact signed offender refusals."""
    import jam_fuzzer_full_offenders_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()],spec='full')


@reference()
def jam_fuzzer_full_pending_disputes(identity):
    """Require real pending-report verdict cancellation, exact hash identity and unchanged late-refusal maps."""
    import jam_fuzzer_full_pending_disputes_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*2,spec='full')


@reference()
def jam_fuzzer_full_population(identity):
    """Require ordinary/skipped full population rotations and independently unchanged marker-refusal maps."""
    import jam_fuzzer_full_population_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.PLANS),spec='full')


@reference()
def jam_fuzzer_full_profile(identity):
    """Preserve both original full-geometry sparse/saturated baseline chains."""
    import jam_fuzzer_full_profile_oracle as source
    return selected(source,identity,[source.parameters()]*2,spec='full')


@reference()
def jam_fuzzer_full_sealing(identity):
    """Require full winner activation, each skipped-tail/epoch fallback and signed marker refusal trace."""
    import jam_fuzzer_full_sealing_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.PLANS),spec='full')


@reference()
def jam_fuzzer_full_tickets(identity):
    """Require both full-population nonempty16-ticket admission chains and every complete map."""
    import jam_fuzzer_full_tickets_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*2,spec='full')


@reference()
def jam_fuzzer_full_verdict_availability(identity):
    """Require post-dispute assurance validation and genuine guest effects with exact late-refusal maps."""
    import jam_fuzzer_full_verdict_availability_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()]*len(source.MODES),spec='full')


@reference()
def jam_fuzzer_full_verdict_populations(identity):
    """Require all parent/current/previous quorum and previous-only evidence-lifetime complete maps."""
    import jam_fuzzer_full_verdict_populations_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()],spec='full')


@reference()
def jam_fuzzer_full_verdicts(identity):
    """Require full good/bad/wonky verdicts and every exact quorum/split/epoch/signature/fault/refusal exchange."""
    import jam_fuzzer_full_verdicts_oracle as source
    from jam_fuzzer_full_profile_oracle import parameters
    return selected(source,identity,[parameters()],spec='full')


@reference()
def jam_fuzzer_guest_forks(identity):
    """Retain the original nonempty Tiny guest siblings and original-last chains."""
    import jam_fuzzer_guest_forks_oracle as source
    return selected(source,identity)


@reference()
def jam_fuzzer_privileged_forks(identity):
    """Preserve privileged host effects and their original explicit profiles."""
    import jam_fuzzer_privileged_forks_oracle as source
    from jam_fuzzer_effect_forks_reference import profiles
    return selected(source,identity,profiles(source.FAMILIES))


@reference()
def jam_fuzzer_seed_guests(identity):
    """Retain nonempty guest effects starting from original complete seed snapshots."""
    import jam_fuzzer_seed_guests_oracle as source
    return selected(source,identity)


@reference()
def jam_fuzzer_supervised_forks(identity):
    """Preserve supervised foreign-account effects with their explicit source-specific deposits."""
    import jam_fuzzer_supervised_forks_oracle as source
    from jam_fuzzer_effect_forks_reference import profiles
    return selected(source,identity,profiles(source.FAMILIES))


@reference()
def jam_fuzzer_transfer_forks(identity):
    """Preserve transfer-bearing families and every independently declared admission profile."""
    import jam_fuzzer_transfer_forks_oracle as source
    from jam_fuzzer_effect_forks_reference import profiles
    return selected(source,identity,profiles(source.FAMILIES))
