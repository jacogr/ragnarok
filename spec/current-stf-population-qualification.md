# Bounded host/population interaction assessment

## Target and authority

Close the unbounded “all host-operation combinations under resizing” item in the
[population coverage record](current-stf-changing-rosters.md) by identifying the
state dependencies which can produce a different result. Completion requires an
explicit disposition for every accumulation host and every identified interaction
boundary, with a focused witness for an uncovered rule. It does not require the
Cartesian product of programs, histories and validator populations.

Authority is Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`:
`text/pvm_invocations.tex`, `eq:accinvocation`, `eq:implications`,
`sec:generalfunctions`, `sec:accumulatefunctions`; `text/accumulation.tex`,
`eq:partialstate`, `eq:accseq`, `eq:accpar`, `eq:accountspostaccdef` and Preimage
Integration; `text/reporting_assurance.tex`, availability, credential and
contextual-validity rules; `text/safrole.tex`, key rotation and blacklist filter.
Published corroborating inputs remain gp-next
`23061ae1f9b51171c01387e7dde0f15794c98e24`. No pin changes or external-client
posterior states are part of this assessment.

Assessment baseline: merged master
`a5e50201aae84e8f5c131a6d56d0c01bc6f1e5f8`. The linked feature contracts retain the original
macOS/Linux comparisons, frozen source identities, profiles and limitations.
Those historical execution results are reused within their recorded scope;
this assessment is not a fresh run of every corpus against the baseline.

## Dependency boundary

The GP accumulation dispatcher admits identifiers 0–6 and 16–29: 21 calls.
Refinement-only identifiers 7–15 take accumulation's unknown-call branch. The
[dispatcher](../src/state/accumulation_dispatch.nim) implements that same partition.

The partial state and invocation context contain accounts, privileges, queues,
staging keys, transfers, provisions and selected regular/exceptional effects.
Hosts do not independently choose a current/previous validator roster or quorum.
Population-dependent work admission, offender filtering and promotion feed the
invocation through available reports, selected inputs, entropy and staging state.
The important cross-boundary questions are therefore which work reaches execution,
which state version execution reads, and which effects publish afterward.

This dependency analysis motivates the finite matrix below. It is a risk
assessment, not a formal noninterference or arbitrary-composition proof. Component
coverage is identified separately from complete signed-transition coverage.

## Complete accumulation-host inventory

Each entry names the state dependency and the narrowest relevant evidence. A row
with component evidence does not assert a whole-block resizing witness for that
specific call. Detailed malformed-input, gas and ownership cases remain in the
linked host contracts and native suites.

| ID / call | Dependency relevant to this assessment | Evidence / disposition |
| --- | --- | --- |
| 0 gas | Invocation gas after its own charge; no roster lookup | [Gas component contract](pvm-host-gas.md), [dispatch suite](../tests/unit/state/test_pvm_accumulation_dispatch.nim); whole-map actual-gas accounting in [late gas](current-stf-late-gas.md) |
| 1 grow_heap | Initialized CPU geometry and allocation policy; no account or roster selection | [Adopted heap contract](pvm-accumulation-heap.md), [heap suite](../tests/unit/state/test_pvm_accumulation_heap.nim); additional resizing cross-product deferred as D1 |
| 2 fetch | Invocation-bound parameters, posterior entropy and selected operands | [Fetch suite](../tests/unit/state/test_pvm_accumulation_fetch.nim); correct source binding is component evidence, further joint histories deferred as D1 |
| 3 lookup | Current regular account's preimage namespace; queued provision is separate | [Lookup suite](../tests/unit/state/test_pvm_accumulation_lookup.nim), [preimage lifecycle](current-stf-rotation-preimages.md); no claim of a literal lookup in every resizing history |
| 4 read | Current regular storage map, including preceding writes | [Read suite](../tests/unit/state/test_pvm_accumulation_read.nim), new same-invocation witness below; [supervised publication](current-stf-rotation-supervision.md) covers the complete-map boundary |
| 5 write | Current effective supervisor, funded footprint, selected account conflict | [Supervision](current-stf-rotation-supervision.md), [authority](current-stf-rotation-authority.md), [foreign funding](current-stf-rotation-funding.md) |
| 6 info | Current regular metadata and derived minimum balance | [Info suite](../tests/unit/state/test_pvm_accumulation_info.nim) includes a preceding storage write; [creation](current-stf-rotation-creation.md) and [upgrades](current-stf-late-upgrades.md) qualify publication separately |
| 16 bless | Current manager versus original publication producer; delayed allowances | [Privileges](current-stf-rotation-privileges.md), [late allowances](current-stf-late-allowances.md) |
| 17 assign | Current assigner and queue replacement versus selected publication | [Privileges](current-stf-rotation-privileges.md) |
| 18 designate | Current delegator, full staging records and delayed pending/active promotion | [Designation](current-stf-rotation-designation.md), [offender-filtered histories](current-stf-rotation-histories.md) |
| 19 checkpoint | Copies regular effects into exceptional effects; subsequent reads still use regular | [Population guests](current-stf-population-guests.md), [supervision](current-stf-rotation-supervision.md), new read witness below |
| 20 new | Entropy/slot-derived allocation, registrar authority, funding and request-only code | [Creation](current-stf-rotation-creation.md), [code activation](current-stf-rotation-code.md), [funding](current-stf-rotation-funding.md) |
| 21 upgrade | Selected current metadata versus report's admission-time code hash | [Authority](current-stf-rotation-authority.md), [late upgrades](current-stf-late-upgrades.md) |
| 22 transfer | Current source pools, recipient existence/code, reentry and held credits | [Transfers](current-stf-rotation-transfers.md), [transfer waves](current-stf-rotation-transfer-waves.md), [late allowances](current-stf-late-allowances.md) |
| 23 eject | Exact incarnation/eligibility, refund pools and removal of namespaces | [Retirement](current-stf-rotation-retirement.md), [supervisor incarnations](current-stf-rotation-incarnations.md) |
| 24 query | Current regular request history, distinct from raw storage | [Query suite](../tests/unit/state/test_pvm_accumulation_query.nim); [preimage lifecycle](current-stf-rotation-preimages.md) qualifies selected histories separately |
| 25 solicit | Current authority and request history, reservation and restoration | [Supervision](current-stf-rotation-supervision.md), [preimages](current-stf-rotation-preimages.md), [reactivation](current-stf-late-reactivation.md) |
| 26 forget | Current authority, exact age, payload removal and reservation release | [Preimages](current-stf-rotation-preimages.md), [posterior relevance](current-stf-late-relevance.md), [reactivation](current-stf-late-reactivation.md) |
| 27 yield | Regular/exceptional selection and junior annulment before commitment | [Population guests](current-stf-population-guests.md), [supervision](current-stf-rotation-supervision.md), [late gas](current-stf-late-gas.md) |
| 28 provide | Selected queued provision, final request relevance, integration after execution | [Supervision](current-stf-rotation-supervision.md), [preimages](current-stf-rotation-preimages.md), [late code](current-stf-late-rotation.md) |
| 29 supervisor | Immediate authority change and creation-slot-bound effective supervision | [Authority](current-stf-rotation-authority.md), [incarnations](current-stf-rotation-incarnations.md), [late incarnations](current-stf-late-incarnations.md) |

## Interaction rules and distinguishing witnesses

The referenced Python tests check independently derived expectations; their
feature contracts record separate native complete-map comparisons. Test names
below identify the exact distinguishing assertion without inventing new corpus
counts or summing overlapping histories.

| Risk | Rule / failure distinguished | Existing executable evidence |
| --- | --- | --- |
| R1 admission at a resize | Prior-population quorum can release work before resize clears assignments; old credentials and current erasure widths have distinct domains | [Reporting tests](../tests/test_current_stf_population_reporting_oracle.py): `test_quorum_uses_prior_population_before_rollover`, `test_resize_clears_without_availability_and_permits_replacement`, `test_erasure_population_and_previous_credential_index_domains` |
| R2 staging and authority | A new staging set cannot change the already-promoted same-block population; role handoff does not replace the original selected producer | [Designation tests](../tests/test_current_stf_rotation_designation_oracle.py): `test_staging_precedes_pending_and_active`, `test_original_delegator_publishes_during_handoff` |
| R3 delayed work and code | Code arrival does not fulfill a package dependency or retroactively execute a processed skip; admitted old-code reports later use current metadata | [Dependencies](../tests/test_current_stf_late_dependencies_oracle.py): `test_code_arrival_alone_never_satisfies_a_package_dependency`, `test_fulfillment_does_not_replay_processed_packages`; [upgrades](../tests/test_current_stf_late_upgrades_oracle.py): `test_old_signed_reports_execute_current_code_after_upgrade` |
| R4 budgets and expiry | Missing-code zero gas differs from genuine execution exhaustion; exact admission can retain work until row expiry | [Gas](../tests/test_current_stf_late_gas_oracle.py): `test_missing_code_and_pooled_exit_have_distinct_preconditions`; [population gas](../tests/test_current_stf_population_gas_oracle.py): `test_exact_residual_changes_processed_prefix`, `test_waiting_reports_can_expire_after_budget_retention` |
| R5 authority and incarnation | Following host calls use immediately changed authority; retiring/recreating an ID cannot inherit a stale supervisor binding | [Authority](../tests/test_current_stf_rotation_authority_oracle.py): `test_handoff_revokes_following_foreign_write_immediately`; [incarnations](../tests/test_current_stf_rotation_incarnations_oracle.py): `test_fresh_incarnation_and_delayed_binding` |
| R6 conflicting effects | Junior annulment discards its yield while a relevant selected provision can survive; rollback changes which modifier publishes | [Supervision](../tests/test_current_stf_rotation_supervision_oracle.py): `test_annulment_discards_yield_but_preserves_queued_provision`; [funding](../tests/test_current_stf_rotation_funding_oracle.py): `test_rollback_or_stale_authority_keeps_junior_write` |
| R7 transfer delivery | Held/forwarded credits are consumed once; unavailable recipient code does not suppress the actual balance credit | [Transfer waves](../tests/test_current_stf_rotation_transfer_waves_oracle.py): `test_active_supervisor_holds_duplicate_credits_for_one_invocation`; [long histories](../tests/test_current_stf_late_histories_oracle.py): `test_sustained_allowances_conserve_each_retained_credit` |
| R8 preimage phase ordering | Final request relevance determines provision integration; strict expiry differs from equality; integration does not execute earlier work again | [Preimages](../tests/test_current_stf_rotation_preimages_oracle.py): `test_queued_provision_requires_relevant_final_request`; [reactivation](../tests/test_current_stf_late_reactivation_oracle.py): `test_exact_age_restores_while_one_past_expunges`, `test_expunge_block_runs_prior_code_and_integration_block_skips` |
| R9 offenders and later epochs | Cancellation removes the actual package; null records preserve configured roster positions and quorum rather than shrinking to surviving signers | [Offenders](../tests/test_current_stf_late_offenders_oracle.py): `test_actual_canceled_package_never_enters_processed_history`, `test_null_promotion_preserves_full_configured_roster_positions`; [histories](../tests/test_current_stf_late_histories_oracle.py): `test_two_later_promotions_keep_positions_and_real_signers` |
| R10 retained history | C15 shifts by accepted blocks, including sparse slot histories, and must retain more than the original test profile allowed | [Histories](../tests/test_current_stf_late_histories_oracle.py): `test_retained_package_history_exceeds_original_profile` |
| R11 continuation trust | Restoration uses captured native bytes with an independently trusted root; authenticated trace import refuses recommitted wrong maps | [Restart](../tests/test_current_stf_late_restart_oracle.py): `test_every_restart_transports_only_the_signed_block_and_trusted_root`; [trace](../tests/test_current_stf_late_trace_oracle.py): `test_all_three_typed_import_refusals_precede_actual_complete_output`; [operator contract](current-stf-late-command.md) |
| R12 current observer map | A read following a write must observe the current regular map, including after checkpoint divergence; panic cannot rewind already observed CPU memory | New native witness in [read suite](../tests/unit/state/test_pvm_accumulation_read.nim), described below; existing [info suite](../tests/unit/state/test_pvm_accumulation_info.nim) observes the footprint after write |

## New witness: current storage reads after checkpoint divergence

The audit found no direct write-then-read sequence in the storage-read suite.
The added witness runs four real guest programs: halt/panic, each with/without an
intermediate checkpoint. They write literal bytes `[81, 82, 83]`, read them,
replace the same key with `[82, 83]`, then read again. Both copies are checked
against those literals, including the untouched destination byte after the
shorter value. The final reported length is two.

Regular storage must contain the replacement. Exceptional storage must contain
the first value when checkpointed, or remain absent otherwise. The prepared
source account and source guest memory must remain unchanged. The witness checks
the dispatcher effects and CPU; it does not substitute for the separate terminal
normalization/publication tests or claim a new complete signed population history.
It targets the stale-map failure mode directly, without another whole-block
Cartesian expansion. No production behavior or default capacity changes are needed.

## Explicit deferrals and reopening conditions

| ID | Deferred scope | Reason / when to reopen |
| --- | --- | --- |
| D1 | Every read-only/general call embedded in every resizing guest and every multi-call permutation | Component source-binding/memory checks and the identified whole-block phase boundaries are separately evidenced. This is not a joint execution claim. Add a joint witness when a changed dispatcher/context source, a concrete counterexample or a newly identified state dependency makes composition a distinct risk. |
| D2 | Every legal population/cardinality, core count, quorum boundary and production-size resource workload | Existing changing-roster histories use a bounded three-core six→nine→six profile. Existing domain checks do not establish joint execution at every legal size or production capacity. Such qualification needs its own finite target. Reopen for a specific supported configuration or boundary failure. |
| D3 | Arbitrary-length adversarial histories and arbitrary host programs | Finite witnesses and longer mixed histories cannot exhaust an unbounded state space. Reopen for a reproducible failure, an explicit invariant/model-checking target, or specification/implementation changes. |
| D4 | Complete JAM/STF, live client/network/finality interoperability and external-client execution | This assessment covers the listed accumulation/population boundaries. Independent protocol subsystems and live integration require separate scope, authorities and acceptance criteria. No full-client conformance verdict follows. |
| D5 | Physical device power-loss qualification | Requires physical hardware unavailable to the maintainer. Portable checkpoint/trace/operator tests retain their actual scope and do not infer physical durability. |

## Completion and verification

The bounded assessment is complete when the 21-call inventory is reconciled with
the pinned GP/dispatcher, R1–R11 evidence references resolve, the new R12 native
witness passes, and changed-document links and formatting pass. D1–D5 remain
explicit limitations with reopening criteria, rather than an instruction to keep
enumerating combinations. A future distinct uncovered rule becomes a concrete
follow-up; it must not be described as already qualified by this matrix.

M1 framing remains complete. Current GP serialization qualification retains its
finite [recorded scope](jam-serialization-status.md); neither statement establishes
complete valid-state relationships, arbitrary STF correctness or full-client
conformance.

Observed verification (2026-10-26): `make unit SUITE=pvm_accumulation_read`
passes on macOS with checked ARC/Clang release and all four added guest variants.
The suite retains its original output contract and 1,000-cycle ARC release check:
2,344,640 occupied bytes before and after. `make format` passes for 4,822 Nim
sources and the Rust crate. The source audit matches all 21 listed identifiers and
names against the pinned GP and actual dispatcher; all 75 matrix links and 26
named Python assertions resolve. Changed-document relative links and
`git diff --check` pass. No native production source, protocol pin or default
policy changes. These local results do not claim a new Linux native-suite run;
exact-head PR Smoke remains separate CI evidence.

Retained local records: `build/db5-qualification-audit.json`,
`build/db5-qualification-read.log`,
`build/tests/native/selected/pvm_accumulation_read.log` and
`build/db5-qualification-format.log`.
