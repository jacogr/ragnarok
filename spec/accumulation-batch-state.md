# Common-source accumulation batch state

## Scope and authority

Build a bounded batch coordinator on [terminal-selected provisions](accumulation-terminal-provisions.md)
for the currently implemented read-only account host calls, checkpoint/yield and deferred provide.
Authority remains Gray Paper 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`accumulation.tex` SHA-256 `bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
particularly the `accone` service input construction, `accpar` self-account merge and subsequent
`fnprovide` application. Pins and protocol interpretations do not change.

Require every completed execution to originate from the exact same immutable prepared input owner
and exact prior complete-map snapshot. Reject repeated invoking services, even when executions
halt or produce disjoint effects. Validate provenance and uniqueness before provision hashing.
The existing terminal adapter verifies invocation slots, selects regular/checkpoint effects and
preserves its readable-32-byte halt/provisions ambiguity gate.

The parent implementation retains credited initial account maps: its supported hosts do not
mutate account metadata, storage, account membership, queues or privileges. The parallel PVM
storage-write API exposes `effectAccounts`; when available, this layer requires the terminal-selected
current account version to match the original credited service version. A different selected map
returns `UnsupportedAccountEffects`, preventing silent loss of those writes. An uncheckpointed write
rolled back by panic is accepted when the selected exceptional account map still matches. Merge only each executed
service's independently prepared incoming-credit metadata into a private fork of the common prior,
then fulfill the selected provision union there. Publish the caller's store only after both phases
succeed. Preserve unrelated accounts, code/storage, opaque chapters and extrinsic statistics.
Compare immutable snapshot identity before application so a stale plan cannot overwrite unrelated
changes or apply incoming credits twice. Equal roots on independently constructed maps do not
establish source ownership. Empty work retains the exact prior without hashing.

This certifies an explicitly selected subset of one prepared input set, not complete `accpar`, an
admitted initial round, aggregate gas accounting or a full block. Missing/uninvoked services, service
creation/deletion, account-mutating hosts, privilege changes and later rounds require subsequent
work. Do not implement a generic whole-map merge or silently claim those unsupported effects.
Account writes have a separate explicit count ceiling; inherited store limits apply independently
to the account and provision phases. The coordinator is atomic across both phases; these are not
new aggregate store-write ceilings.

## Completion tests

Use two genuinely executed services sharing one prepared input owner and prior map, with distinct
incoming transfers. Check literal final balances, request histories, blobs and complete-map roots
for halt and checkpoint rollback. Refuse foreign input owners, equal-root foreign snapshots,
duplicated services, default/local-failed executions and wrong invocation slots before union hashes.
Check subset/empty batches, exact/short budgets, no-op identity queries, retained-source lifetime,
metadata isolation, stale/changed/equal-root publication gates, and failures in both private phases.
Verify late provision/root refusal never publishes earlier account credits and repeat successful
preparation/application and refusal cleanup for 1,000 ARC cycles. Add source-owned privacy, nominal
and strict runtime guards; run affected service/store/terminal consumers only.

M1 framing completion remains unchanged; complete state serialization parity and accumulation/block
publication remain outside this bounded increment.

## Implemented API and ownership

`prepareAccumulationBatch` accepts the prepared input owner, exact prior snapshot, actual completed
executions, one candidate slot and independent account/union limits. Default sources and descriptor
extents are checked before allocation. Every execution must retain that exact input and prior owner;
invoking service IDs are sorted only to detect duplicates, without changing source extraction order.
Changed post-credit self metadata is encoded under the account-write ceiling. The terminal adapter
then performs actual outcome selection, slot verification and bounded union preparation once.

`sameStateSnapshot` and `sameAccumulationInputs` are hash-free initialized-owner comparisons;
defaults never match, copied handles do, and independently prepared equal contents do not.
`serviceSourceMatches` proves both source owners without exposing raw references. These are local
preparation/publication contracts, not extra guest outcomes or protocol validity conditions.

`batchInfo` returns copied subset/write/terminal observations. `batchOutcomeAt` retains the exact
normalized outcome at a nominal input-execution ordinal. Plans privately retain input/prior owners,
encoded metadata and selected provisions; no write buffer or replaceable source is exported.

`applyAccumulationBatch` requires the caller's current snapshot to be the retained prior. It forks
that complete map, applies the fixed metadata batch, and invokes the existing terminal-bound
provision kernel on the credited candidate. Only then does it replace the caller's store. The
account phase retains `StoreFailure` and its original reason; terminal preparation/application
retains `TerminalFailure` with guarded normalization/provision subreasons. Defaults and all other
refusals expose no payload. Empty batches retain the original version without hashing; a successful
nonempty application makes the old plan stale, preventing credit replay on that successor.

## Local verification

Passed `make unit SUITE=accumulation_batch`, `accumulation_terminal_provisions` and
`accumulation_service`. The new suite checks two independently credited services sharing the exact
input/prior owners, full expected roots and literal balances/history/blob values, input order
permutations, executed subsets, checkpoint rollback, zero-credit/empty work, late slot/normalization
gates, foreign equal-content sources, duplicate services, stale publication and detached ownership.
Write limits and injected backend failures cover both private phases, including refusal after the
entire account candidate was computed. Its 1,000-cycle ARC workload retained 1,027,520 occupied
bytes before/after; the direct consumer workloads retained 421,904 and 15,632 bytes respectively.

Twelve strict runtime extraction guards and six privacy/nominal compiler rejections passed.
Nested reason guards reject the wrong terminal subalternative as well as the wrong outer tag.
Python discovery passed 441 tests with six skips; source-owned inventory/provenance, pinned
formatting and diff checks passed. All declarations are local to their suite/guard/failure files;
no shared harness or inventory changes were required. Logs are retained under
`build/accumulation-batch/`. These are local macOS checks, separate from exact-head Linux CI.

The [complete-input extension](accumulation-complete-batch.md) now adds certified skipped-service
credits and exact coverage checks. Actual service-indexed gas accounting and admitted-round binding
remain next, before later rounds and block publication. PVM storage writes already retain versioned account effects in their own stack. Merging those
effects remains subsequent work and is protected here by `UnsupportedAccountEffects`; supported
batches cover immutable account backing plus incoming credits and deferred preimage provisions.

An isolated combined-tree native check against PVM storage-write PR #153 at
`6bf4180d46783dd769962da476aa3aa7b670d119` also passed the complete batch suite. Actual guest
storage writes followed by halt or a retaining checkpoint/panic are refused; a regular write
rolled back to an unchanged exceptional checkpoint succeeds with the full expected final map.
The `when declared(effectAccounts)` capability check supports both this layer's current parent
and that concrete PVM API without changing the PVM branch. Integration logs and source overlays
are retained under `build/accumulation-batch/`; the temporary checkout was removed.

## Self-metadata publication extension

The self-metadata extension in [PVM account publication](pvm-account-publication.md) now permits terminal-selected upgrade-only lineages. The coordinator copies each invoking service's own credited metadata, while broader mutations remain UnsupportedAccountEffects. It retains exact common-source provenance, unique service keys and atomic provision integration.
