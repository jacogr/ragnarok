# Focused compiler Guards review — October 30, 2026

Audit base: `9619c3971042a370f682ab9d7500090575f975b8`. This is a selection audit, not a compiler qualification claim.

| Predicate family | Before | After |
| --- | ---: | ---: |
| Privacy/accessor | 2,086 | 0 |
| Nominal | 523 | 2 |
| Ownership/lowering | 68 | 11 |
| Static contracts | 12 | 0 |
| Scalar schemas | 5 | 1 |
| Total | 2,694 | 14 |

## Individual retained justifications

Each row is also enforced as a source-local rationale/reference. No category was retained wholesale.

| Fixture | Distinct defect or unsafe consumer behavior | Evidence or consumer |
| --- | --- | --- |
| [application_download_stream_array_copy](../tests/native/compile_fail/application_download_stream_array_copy.nim) | Array-to-sequence conversion used to copy the live callback owner, duplicating callback retirement authority while the original stream remained live. | [spec/nimony-nightly-2026-10-21.md](../spec/nimony-nightly-2026-10-21.md) |
| [disk_worker_copy](../tests/native/compile_fail/disk_worker_copy.nim) | Returning a borrowed disk worker would duplicate synchronization state and a native thread that retains the original worker address; closing either alias could race the live borrower. | [src/app/disk/worker.nim](../src/app/disk/worker.nim) |
| [nimony_scalar_copy](../tests/native/compile_fail/nimony_scalar_copy.nim) | A scalar-only owner used to bypass unavailable copy/dup hooks without a destructor; preserve the original lowering regression. | [spec/nimony-nightly-2026-10-21.md](../spec/nimony-nightly-2026-10-21.md) |
| [nimony_sequence_copy](../tests/native/compile_fail/nimony_sequence_copy.nim) | Derived sequence duplication used to ignore an element error copy hook and corrupt retained owner values; cover the implicit derived-dup path (Nimony #2737). | [spec/nimony-nightly-2026-10-21.md](../spec/nimony-nightly-2026-10-21.md) |
| [nimony_sequence_copy_dup](../tests/native/compile_fail/nimony_sequence_copy_dup.nim) | Sequence duplication used to bypass even explicit error copy AND dup hooks; preserve this second original #2737 reproduction rather than infer it from the copy-only case. | [spec/nimony-nightly-2026-10-21.md](../spec/nimony-nightly-2026-10-21.md) |
| [offload_pool_copy](../tests/native/compile_fail/offload_pool_copy.nim) | The offload-enabled native proof pool lends its stable stack address to joined workers; duplication would split cancellation, lock and worker-join authority. | [src/jamnp-s/offload.nim](../src/jamnp-s/offload.nim) |
| [pvm_gas_memo_context_alias](../tests/native/compile_fail/pvm_gas_memo_context_alias.nim) | The host callback replaces its mutable context memo while executeWithHost borrows that same memo for metering; alias acceptance would invalidate the active gas-policy borrow. | [src/pvm/step.nim](../src/pvm/step.nim) |
| [pvm_gas_plan_context_alias](../tests/native/compile_fail/pvm_gas_plan_context_alias.nim) | The host callback replaces its mutable context plan while executeWithHost borrows that plan for prepared gas charging; alias acceptance would invalidate execution policy during reentry. | [src/pvm/step.nim](../src/pvm/step.nim) |
| [pvm_import_inputs_source](../tests/native/compile_fail/pvm_import_inputs_source.nim) | bindImportInputs must demand original verified extrinsic ownership; accepting a bare work package would bypass authentication and original-package provenance before binding imported leaves. | [src/state/import/inputs.nim](../src/state/import/inputs.nim) |
| [state_account_audit_plan_partial](../tests/native/compile_fail/state_account_audit_plan_partial.nim) | Whole-state account auditing must demand complete logical inventory; accepting a partial StateStoreSnapshot would omit absent accounts and preimages while planning an exhaustive audit. | [src/state/account/audit/plan.nim](../src/state/account/audit/plan.nim) |
| [storage_file_copy](../tests/native/compile_fail/storage_file_copy.nim) | Returning a borrowed repository owner would duplicate descriptor retirement authority; a second close can close an unrelated descriptor after OS descriptor reuse. | [src/storage/file/repository.nim](../src/storage/file/repository.nim) |
| [storage_full_paged_candidate_copy](../tests/native/compile_fail/storage_full_paged_candidate_copy.nim) | A sealed full-state candidate owns authoring, publication and cleanup authority; returning a borrowed copy could publish or retire the same candidate twice. | [src/storage/full/paged/store.nim](../src/storage/full/paged/store.nim) |
| [storage_light_view_escape](../tests/native/compile_fail/storage_light_view_escape.nim) | Returning encoded snapshot bytes borrowed from a local prepared snapshot would leave replay/checkpoint consumers holding a dangling buffer after the owner dies. | [src/storage/light/snapshot.nim](../src/storage/light/snapshot.nim) |
| [unsupported_collection_scalar](../tests/native/compile_fail/unsupported_collection_scalar.nim) | The collection decoder admits only closed canonical scalar codecs; admitting mutable heap-backed strings would bypass the fixed scalar encoding/ownership contract for retained canonical sets. | [src/codec/collections.nim](../src/codec/collections.nim) |

## Removal decisions

Private-field access, private result forging and assigning read-only accessors were removed even
when their filenames described important subsystems: those fixtures only restated the language
rule. Examples include `state_current_refresh_execution_status_private`, `private_collection_commit`,
and the numerous per-result `completed`/reason/initialized-field checks. No documented defect
or distinct lowering behavior justified their repetition. Production visibility stays unchanged.

Ordinary index/hash/slot/count substitutions and interchangeable intermediate-stage matrices were
removed, including `request_length_as_slot`, `state_key_as_hash`, `unsigned_as_full_header` and
all but the two named terminal provenance/admission boundaries above. The two retained cases
protect original authenticated-package provenance and exhaustive whole-state audit planning;
they do not authorize a fixture for every pair of nominal types or adjacent stage.

All static-contract fixtures used a known absent/failure state or a plainly invalid constant
against an existing precondition; examples are `assignment_known_absent_guarantee` and
`pvm_static_scalar_store_width`. Four scalar-width schema checks duplicate that rule. The retained
schema witness instead protects the application-defined closed canonical scalar family from
mutable heap-backed payload admission. Preconditions and runtime Contract checks remain unchanged.

Ownership was reviewed by mechanism. Routine direct copies of each server/session/worker wrapper
were removed, including `mcp_server_copy`, `logging_copy` and `application_download_stream_copy`.
The actual array conversion regression remains. `storage_light_view_mutate` and the delta mutation
fixture were removed as read-only accessor assignments; `storage_light_delta_view_escape` repeats
the local-owner escape mechanism retained in `storage_light_view_escape`. Descriptor, fixed-address
worker, offload ABI and sealed publication authority retain individual witnesses rather than all
file/repository/checkpoint wrapper copies. Existing source hooks and destructors are untouched.

## Verification and timing

Local checks use Python inventories, mocked harnesses and Make dry-runs only. Native compiler
checks run on CI. Source-local rationale/reference metadata and exact report identities are
validated before setup; unrelated errors and successful compiles fail the retained predicates.
Runtime Contract plans and ordinary native unit inventories are compared to the unchanged base.
No removed fixture matrix is moved to another suite or schedule.

Timing is measured from CI evidence and reported in the PR; fixture count reductions alone are
not a runtime speedup measurement. No unresolved compiler behavior is silently accepted as a pass.

## JAMNP-S integration review

Integrating master `d249a685e8970994877f7c22de8c97a982fb9798` adds seven privacy fixtures
and one direct `MessageReader` copy fixture to the earlier audit base: 2,702 incoming fixtures
(2,093 privacy, 523 nominal, 69 ownership, 12 static contracts and five schemas). The retained
set remains 14; the earlier table records the original snapshot rather than this later integration.

The new audit/message result tags and payload/batch fields are ordinary private-field accesses.
They demonstrate no distinct compiler defect, so all seven are removed. `jamnp_message_reader_copy`
only assigns an ordinary copy-banned parser and uses both bindings. Its sequence storage and cursor
budget do not introduce a native fixed-address borrower, callback retirement, owner escape or
new lowering reproduction; it repeats the direct-owner copies removed above. The parser grants
no authentication or state authority. Remove that fixture while preserving its production copy/dup
restrictions and all incoming parser, budget, audit and runtime Contract tests.

All 80 modified incoming Guards change import paths/quoting only. Preserve deletion of the 78
already rejected fixtures; update the two retained regression imports for `src/jamnp-s/` and the
offload rationale reference. Runtime fixture and ordinary unit additions from master remain intact.
