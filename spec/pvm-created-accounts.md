# Terminal-selected created-account publication

## Scope and authority

Extend PR #198 using GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex `accpar` new-account set n and `fnprovide`, with vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` unchanged. Publish genuine new (19)
children under explicit per-execution and batch created-account ceilings. Zero
preserves the earlier successful local execution and UnsupportedAccountEffects gate.

Each actual successful creation captures only its selected service and canonical
empty code-request key in a private bounded immutable owner, after a count/native
extent preflight and before candidate map hashing. Metadata and request bytes come
from the same terminal-selected account map as the creator's debit. Checkpoints
retain creation proof, cursor and accounts together. Self storage/request changes,
upgrades, yield and provide preserve an existing creation proof; any ejection,
transfer or privilege mutation keeps the lineage unsupported.

For every selected child, prove its metadata key was absent from the exact shared
prior before copying its complete metadata and still-empty code request. Reject
physical write conflicts, including two independent guests creating the same ID;
never choose a winner or silently discard a creator debit. Apply the bounded child
writes, self metadata and self writes privately, then fulfill terminal provisions.
Only full success publishes. Existing source/coverage/slot, stale-owner, metadata,
self-key/value and store limits remain independent; created accounts are counted
separately. No whole-map traversal or generic account merger is introduced.

Ejection/deletion remains UnsupportedAccountEffects: deleting accounts involved in
other executions/skips and deletion-versus-creation require a separate bounded
contract. Outgoing transfers, privilege/queue/staging changes and grow_heap remain
gated. M1 framing is complete; full state serialization, full accpar, recursive
transfers and whole-block publication remain open.

## Completion tests

Use real two-service PVM executions with literal creator debits and child balances,
canonical metadata/request records and independent complete-map roots. Cover halt,
panic/checkpoint rollback, repeated creation/cursor advancement, proof preservation
through self writes and upgrade, provisions to a new child, zero/short/exact budgets,
foreign/stale owners, collision refusal, detached owners and early/late backend
failure. Repeat execution/preparation/publication for 1,000 fresh ARC cycles.
Retain default/index/private/nominal guards and existing gates; reuse prepared
native dependencies and run affected consumers rather than unrelated suites.

## API and bounded publication

`prepareAccumulationEffects` and `executeAccumulationMachine` append an independent
`createdAccounts: ElementLimit` policy. The same-named batch limit bounds selected
children across all executions; each child copies exactly 89 metadata bytes and
one empty-request byte into two descriptors. Store limits still bound the complete
combined account phase separately. `accounts` and `batchInfo.accountWrites` continue
counting only invoking metadata records; self-key/value counts are unchanged.
`batchInfo.createdAccounts` counts the new children without conflating them with
self writes or invoking-service input coverage.

The immutable CreatedAccounts scope owns fixed `AccumulationCreatedAccount`
facts: actual service ID and captured request key. `effectCreatedAccountCount`
and `effectCreatedAccountAt`, indexed by `AccumulationCreatedAccountIndex`, return
copied observations from the same retained context. Defaults, unsupported lineages
and invalid full-width indices expose no payload. Copied facts cannot modify the
owner and no public API accepts caller-constructed facts as a proof.

The collision fixture freezes automatic child ID 1197275345 for service 42 with
entropy counter 14592 and service 99 with counter 94245, at slot 128. Counters are
little-endian in the first four entropy bytes; the rest are zero. Both real guests
produce that ID. These are explicit lower-level bootstrap entropy arguments; the
batch contract certifies common input/prior ownership and slot, not an admitted
round's common entropy. Either execution order refuses the duplicate physical
child keys. The offline bounded birthday search is not repeated in normal tests.
This local conflict gate neither chooses a protocol collision winner nor expands
whole-round certification.

Ejection is deliberately left for the next layer. A real aged account owned by the
invoker is removed locally by the new suite, producing UnsupportedAccountEffects
when selected; a checkpoint before that deletion followed by panic retains only
the supported child/debit and preserves the original target. This freezes the
boundary without guessing existing-account deletion versus other service work.

## Verification scope and efficiency

The new native suite passed with unchanged 171,808 occupied bytes across 1,000
fresh guest/preparation/publication cycles. It uses fixed literal funding (one unit
per child), complete independently authored maps, genuine checkpoint/cursor
selection, no-credit creators, self writes/upgrades, child provisions, detached
owners, stale/foreign provenance and early/late backend failure. A selected real
ejection remains refused and its unselected regular changes are rolled back.

Existing prepared native libraries, guest framing, batch fixture, native runner and
focused guards were reused. The bounded offline collision search took about 0.1
seconds and yielded fixed native-test inputs; normal tests do not search. Source
formatting joined a wrapped boolean token, corrected by two explicit validation
branches; the new fixture also needed the owning entropy-type import. No compiler
patch or dependency setup was used. The unchanged passing new-suite run was
retained while the seven affected consumers ran separately, avoiding another
unnecessary full rerun. Complete Linux verification remains in CI.

## Local verification (2026-10-19)

Eight native suites passed: pvm_created_accounts, accumulation_batch,
accumulation_complete_batch, pvm_self_account_writes,
pvm_account_publication, pvm_accumulation_integration,
pvm_accumulation_new and pvm_accumulation_eject. All retained fresh stable
1,000-cycle ARC evidence. Fifty-six runtime extraction guards across effects,
batch and dispatch, twelve privacy rejections, the nominal created-account index
rejection and ten attached API-documentation checks passed.

Four downstream modules passed semantic compilation: accumulation_execution,
accumulation_outputs, accumulation_continuation_execution and
accumulation_reentry_execution. Sixteen selected failure/inventory Python tests,
source-owned inventory, pinned Nim/Rust formatting and whitespace checks passed.
Native bridges and vendor pins are unchanged. These are focused local macOS
results, separate from exact-head Linux CI.

Evidence is under `build/pvm-created-accounts/`: native.log, regression.log,
guards.log, guards-results.json, downstream.log and individual semantic logs,
collision-witness.json, inventory.log, python.log and format-check.log. The final
source edits after native verification updated comments only, with targeted pinned
formatting checks; passing behavior checks were retained rather than repeated.
Next bounded work is ejection/deletion provenance and explicit conflict rules for
accounts also represented by other executions/skips. Grow_heap stays gated.

## Bounded ejection extension

[Deleted-account publication](pvm-deleted-accounts.md) now captures successful
ejections under a separate zero-default execution/batch limit. It preserves
creation proofs and publishes removals/beneficiary credits only for targets outside
represented service work. Participating-target and prior-ID recreation conflicts,
outgoing transfers, privilege changes and grow_heap remain gated.
