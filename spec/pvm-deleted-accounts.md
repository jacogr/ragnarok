# Bounded terminal-selected ejection publication

## Scope and authority

Extend PR #200 using GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex `accpar` removal set m, post-union removal and `fnprovide`.
Vectors remain `d3c089c9a1d5352ad353626d7a2db8589f137b2a`; no pins, host
eligibility, request namespaces or allocation rules change.

An explicit per-execution deleted-account ceiling captures fixed target/request/
preimage keys only from actual successful eject (22) calls, before candidate-map
hashing. Zero retains prior local success and UnsupportedAccountEffects publication.
The immutable scope/proof accompanies the exact account version and beneficiary
credit through checkpoints, self writes, upgrades, creation, yield and provide.
Other unsupported mutations remain sticky. No partial proof can authorize a merge.

Batch deleted-account count is independent of invoking metadata, creations, self
keys/values and terminal provisions. Require targets to exist in the common prior
and remain absent in the selected account map. Copy explicit metadata/request/
preimage deletions, deduplicating only identical request/preimage keys under the
parked encoding. Existing physical conflict checks refuse duplicate writes. Merge
the actual beneficiary metadata and all supported account effects privately before
fnprovide; publish only after complete success.

Deletion of a service represented by another execution or certified skip remains
UnsupportedAccountEffects, including incoming-credit skips. These are local scope
refusals, not guest return codes or guessed deletion precedence. Prior-present
accounts recreated in the selected final domain use the bounded projection below.
Explicit subset batches
may delete an omitted service: that API intentionally publishes no omitted-service
work/credit and does not certify complete accpar. Targets not participating in the
batch can be deleted normally. No whole-map scan or generic account merger.

Grow_heap, outgoing transfers and privilege/queue/staging changes remain gated.
M1 framing is complete; full serialization, complete accpar/round certification,
recursive transfers and whole-block publication remain open.

## Completion tests

Execute real eligible ejections with target metadata, exact two-slot histories and
present preimages. Compare complete independent maps and literal beneficiary
balances for halt, panic/checkpoint rollback, repeated distinct targets and both
execution orders. Cover self-write/upgrade/create/provide composition, zero/short/
exact budgets, stale/foreign owners, detached proofs and early/late root refusal.
Use a genuine missing-code skip with incoming credit to freeze the participating-
target conflict gate, including explicit subset behavior. Refuse deletion/recreation.
Run fresh 1,000-cycle ARC cleanup plus affected native consumers and strict default,
index, privacy, nominal and attached-doc guards. Reuse existing prepared libraries.

## APIs and ownership

`prepareAccumulationEffects` and `executeAccumulationMachine` append an independent
`deletedAccounts: ElementLimit` policy. Positive capacity exhaustion returns local
LimitExceeded before candidate account hashing; zero retains the earlier local host
success and publication gate. The same-named batch limit bounds aggregate targets.
`batchInfo.deletedAccounts` counts removed accounts separately from invoking
metadata, created accounts and self writes. Each target adds at most three fixed
Delete descriptors, with no payload-copy budget or value buffers.

Private immutable DeletedAccountsData retains copied successful-ejection facts,
not prior effect graphs or mutable snapshot storage. `effectDeletedAccountCount`
and `effectDeletedAccountAt`, indexed by nominal AccumulationDeletedAccountIndex,
return copied observations in the same selected context. Unsupported/default and
invalid-index results expose reasons only. No public operation consumes caller-
constructed deletion facts as a certificate. Creation after deletion and deletion
after creation preserve both traces; self writers/upgrades preserve membership scope.

The common input/prior and slot proofs are unchanged. The sorted represented-service
set includes executions and certified skips. Any deletion naming that set remains
a local UnsupportedAccountEffects gate before account publication. Prior-present
recreation requires matched creation/ejection provenance and final membership as
specified in the bounded extension below. Final keys
still pass the complete physical duplicate-key gate. Exact prior identity protects
stale application and prevents double reclamation even if roots match.

## Local verification (2026-10-19)

Native stack sync first fast-forwarded master to 3bde377 and reconciled the four
published PVM layers using gh-stack. The maintainer restack changed CI/docs/tooling
only; PVM implementation trees were unchanged before this bounded layer.

Eight native suites passed: pvm_deleted_accounts, accumulation_batch,
accumulation_complete_batch, pvm_created_accounts, pvm_self_account_writes,
pvm_accumulation_eject, pvm_accumulation_integration and
accumulation_terminal_provisions. Every suite retained fresh stable 1,000-cycle
ARC evidence; the new workload stayed at 159,344 occupied bytes. Complete-map
roots cover actual prior metadata/request/preimage removal, literal beneficiary
credits, checkpoint selection, repeated targets, both creation/ejection orders,
self changes, provisions, subset/skip conflicts, recreation refusal, detached owners,
independent budgets and early/late private-phase backend failures.

Fifty-nine runtime extraction guards across effects/batch/dispatch, thirteen privacy
rejections and one nominal deletion-index rejection passed. Pinned parser metadata
confirms ten attached API docs. Four downstream modules passed semantic compilation:
accumulation_execution, accumulation_outputs, accumulation_continuation_execution
and accumulation_reentry_execution. Sixteen selected failure/inventory Python tests,
source-owned inventory, pinned Nim/Rust formatting and whitespace checks passed.
Native bridges and vendor pins remain unchanged. These are local macOS results;
exact-head CI remains separate, including the newly merged operating-system matrix.

Evidence is under `build/pvm-deleted-accounts/`: stack-before.json, regression.log,
guards.log, guards-results.json, downstream.log and per-module semantic logs,
inventory.log, python.log and format-check.log. Final source edits after execution
verification updated comments only and passed targeted pinned formatting checks.

Efficiency: existing guest framing, complete-map fixtures, native libraries and
focused drivers were reused. Native stack reconciliation preserved unpublished
work and avoided manual history repair or a repeated PVM exploration. Formatter
instability in long argument layouts and a compound key-filter predicate was
resolved with explicit lines and a short fixed-key loop, without patching tools.
No unrelated dependency setup, whole-source sweep or native corpus rerun was used.
The reverse creation/ejection order was added before the final affected-suite run.
Next: participating-target deletion precedence and prior-ID recreation semantics;
grow_heap remains gated. M1 framing stays complete, with full serialization open.


## Participating-target precedence review (2026-10-19)

Bounded scope: investigate the participating-target gate against the same pinned
GP 0.8.0 revision and vector revision above. Completion requires pinned-source
checks, an independent set witness, the genuine missing-code native regression
with and without incoming credit, and an explicit pending protocol-parity test.
No publication rule or dependency pin changes in this increment.

In `accumulation.tex`, `eq:accpar` defines the final accounts as
`fnprovide((accounts union n) minus m, provisions)`. Its following paragraph says
that different services contributing the same new, altered or removed index make
the block invalid, and asserts removed/altered overlap cannot occur because a
removable service cannot execute. `pvm_invocations.tex`, `eq:accinvocation`, however,
returns the post-transfer state even when code is unavailable. Thus nonexecution
does not prove the absence of an account alteration: incoming credit survives.

The existing native witness has invoker 42 with balance 10 and target 99 with
balance 20, owned by 42 through its E32 code hash. Target 99 has the required two
items, expired two-slot request and present request preimage, but no executable
code. Incoming transfers independently credit 42 by 7 and 99 by 11. Invoker 42's
successful eject reclaims the common-prior target balance 20, leaving 37. Target
99's certified missing-code skip retains balance 31. The invoker contributes 99
to m while the target contributes its credited self record to n. Applying just the
set formula removes 99, discarding its eleven-unit incoming credit; the collision
paragraph instead appears to require invalidity for this altered/removed overlap.
Neither an extra beneficiary credit nor resurrection follows from the formula.

Even without incoming credit, n's self-account projection retains the unchanged
target, while the prose speaks of altered accounts. Whether that unchanged
contribution triggers collision invalidity needs an explicit interpretation too.
Prior-ID recreation is distinct: a target deleted and recreated in one selected
poststate is present in its final domain, so that execution does not contribute
that target to m. An eject event journal alone cannot be used as the GP removal
set in that case. A selected-domain check remains necessary; the bounded extension
below implements the present-final projection.

`tests/test_pvm_deletion_spec.py` pins both source hashes, verifies these relevant
clauses, and models only the set/domain arithmetic with literal balances. Its
pending test records the unresolved validity decision; it does not implement a
Python protocol runtime. The native `participating_skip_conflict` case preserves
the local UnsupportedAccountEffects refusal for both credited and uncredited
skips, checks actual selected/skip balances and exact prior ownership on refusal,
and retains independently checked explicit-subset publication.

Disposition: retain the conservative local gate; do not report protocol invalidity
or deletion precedence as implemented. Resolve the collision paragraph versus the
post-union removal formula for participating skips before extending publication.
The separate bounded increment below addresses prior-ID recreation from selected
final membership, including request replacement and self metadata provenance.
M1 framing remains complete; full serialization remains open.


Verification for this review: focused native `pvm_deleted_accounts` passed with
fresh 1,000-cycle ARC evidence at 159,344 occupied bytes before and after. Three
active Python checks passed and one protocol-parity check remains intentionally
pending. Source inventory, affected-test pinned formatting and whitespace checks
passed. Logs: `build/pvm-deletion-precedence-native.log`,
`build/pvm-deletion-precedence-python.log` and
`build/pvm-deletion-precedence-inventory.log`. These are local macOS results.
The Make entry point attempted unrelated LSQUIC initialization; it was stopped
and the new checkout returned to its prior uninitialized state. The existing
focused native driver then passed using its declared crypto preparation. No
production source, vendor gitlink, toolchain or registry changed.


## Bounded prior-ID recreation projection

Scope and authority: the same pinned GP 0.8.0 `eq:accpar` definitions of n and m.
The successful-ejection journal proves mutation provenance, but m depends on the
selected final domain. If a prior-present, nonparticipating target is recreated
by a genuine captured new call and retains final metadata, it is not removed.
The foreign recreated record is excluded from n because that ID existed in the
common prior and is not the invoking service. Preserve the entire common-prior
target representation; publish only the invoking service's actual selected
metadata, including the reclaim and creation debit. No new balance adjustment is
invented. This can preserve the old target while retaining its reclaimed balance
in the invoker, as the two account projections explicitly specify.

Require matched private creation/ejection facts and supported selected scope.
Keep participating targets, absent-final children, duplicate physical writes and
other unsupported histories gated. Aggregate created/deleted policy ceilings
bound all captured facts inspected, including ignored recreation facts; batch
info counts only accounts actually added or removed. This supersedes the earlier
blanket prior-present recreation refusal, without resolving participating skips.

Completion tests: real registrar-authorized delete/recreate with literal balances,
independent complete maps, both execution orders, halt/panic/checkpoint selection,
selected self-write/upgrade/provide composition (including a provision accepted
against a local recreated request but ignored against the preserved prior request),
short/exact captured-fact budgets, terminal extraction, detached/stale owners and early/late backend failure. Retain
fresh 1,000-cycle ARC evidence and affected batch/creation/integration consumers.
M1 framing remains complete; full serialization remains open.


Local verification (2026-10-19): seven native suites passed: pvm_deleted_accounts,
accumulation_batch, accumulation_complete_batch, pvm_created_accounts,
pvm_self_account_writes, pvm_accumulation_integration and
accumulation_terminal_provisions. All retained fresh stable 1,000-cycle ARC
evidence; the expanded deletion/recreation workload used 244,576 occupied bytes
before and after. Fifteen strict batch extraction guards and semantic checks of
accumulation_execution, accumulation_outputs, accumulation_continuation_execution
and accumulation_reentry_execution passed. Three independent Python checks passed
with the participating-skip parity test intentionally pending. Inventory, affected
pinned Nim formatting and whitespace checks passed. These are local macOS checks;
exact-head CI remains separate. Vendor gitlinks and native bridges are unchanged.

Evidence: `build/pvm-prior-id-recreation-native.log`,
`build/pvm-prior-id-recreation-regressions.log`,
`build/pvm-prior-id-recreation-final.log`,
`build/pvm-prior-id-recreation-guards/results.json`, and matching Python, inventory
and format logs. The final log includes passing guards/semantic checks followed
by the superseded three-byte provision-fixture refusal; the native log records
the final passing one-byte witness within unchanged copy policies. The scratch
guard driver initially omitted its report list, then reran only unfinished checks.
Compact signed immediates fixed the authored combined-program size without
widening guest framing, and existing prepared native libraries were reused.

Next bounded work: grow_heap host integration under explicit resource limits.
Participating-target collision validity remains an independent specification gate.
M1 framing stays complete; full serialization, complete accpar and whole-block
publication remain open.
