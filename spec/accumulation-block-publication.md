# Guarded publication of supported accumulation state

## Scope and authority

Publish the supported [composed accumulation candidate](accumulation-consensus.md) only on a
handle retaining its exact original parent snapshot. Authority and pins remain those of the
composed GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` candidate and the
[complete-map store](state-store.md). This adds a local single-threaded publication/ownership
contract, without changing protocol equations, codecs, domains, pins or PVM behavior.

## Contract

`publishAccumulationState(state: var StateStore, source: PreparedAccumulationConsensus)` accepts
only a genuinely prepared composed candidate. Derive the original admitted parent from its retained
consensus/authorization/preimage/activity/validator/timestamp/finalization/report/block graph.
Require an initialized target store whose current snapshot has the exact same immutable owner as
that admitted parent. Root/byte equality is insufficient: independently rebuilt equal maps and a
store changed and restored to the same root must refuse. An already published successor is stale,
so replay cannot consume or replace that same handle again.

After all checks, fork the candidate's complete immutable snapshot with inherited resource policies
and assign the target handle once. Return that exact snapshot, not a reconstructed equal map. No
serialized payload copying, hashing, signature verification, guest replay or state recomputation
occurs at publication. Hash-provider refusal therefore cannot invalidate a fully prepared candidate.
There is no new policy override: the prepared successor already passed its inherited map/write
limits, which remain attached to the adopted store for future operations.

Invalid/default sources and stale heads return reason-only alternatives; store initialization or
fork refusal has a separately guarded StateStoreError. Every refusal leaves the target handle,
original parent, prepared candidate and other store aliases unchanged. Successful publication
updates only the supplied handle: other handles retaining the parent are independently publishable
branches. The result snapshot and adopted store retain the candidate map without requiring the
preparation graph to remain alive. This is not cross-thread synchronization or an OS/database commit.

This publishes the supported report-only state path. It does not remove unsupported transfer/
account/privilege gates in preparation, run a full block executor, add persistence, or implement
light-node partial-state publication. M1 framing is complete; full state serialization and full
accumulation/block parity remain open.

## Completion tests

Prepare real signed empty, incoming, available/lookup/guest, culprit, epoch and ticket histories
through composition. Publish only on the exact parent and require identity equality with the
prepared complete successor and returned snapshot, preserving old aliases and historical views.
Perform publication with hashing refused and require zero hash calls. Reuse existing composed
root/entry oracles; identical snapshot adoption is stronger than recomputing the same root here.

Refuse invalid/default plans and default stores, wrong parents, stage/earlier-candidate handles,
independently built equal-root parents, updated-and-restored equal-root versions and replay.
Prove refusal leaves the exact target owner unchanged. Permit publication independently on two
handles that both retain the exact parent. Check that a seven-write preparation policy remains a
seven-write limit after adoption and that retained snapshots outlive both plan and store handles.
Require 1,000 ARC success/replay/default-store/invalid-source cycles with zero hash calls, strict
result extraction/privacy/nominal probes, source-owned registration, selected native tests,
Python/inventory and pinned formatting. Reuse unchanged preparation and store algorithm evidence.

## Local verification

Passed `make unit SUITE=accumulation_block_publication`. Genuine signed empty, incoming, combined
available/lookup/real-guest, culprit, epoch and ticket histories publish the exact prepared complete
snapshot, with identity equality for the target handle and returned value. Publication and replay
perform zero Blake2b calls while hashing is refused. Historical views and untouched parent aliases
remain valid; independent handles retaining that exact parent may each publish their branch.

Independently rebuilt equal-root parents, changed roots, changed-and-restored equal roots,
authenticated stage handles, earlier accumulation handles and replay all refuse without changing
the target owner or hashing. Invalid/default sources preserve initialized targets; default stores
retain the selected Uninitialized store reason. A seven-write preparation policy remains active:
eight distinct later Puts refuse before hashing while seven pass. Result snapshots survive release
of the preparation graph and target handle. The 1,000-cycle success/replay/default-store/invalid-
source workload retains 341,792 occupied bytes before and after, with zero publication hash calls.

Three strict runtime extraction guards and five compiler privacy/source-type rejections pass.
Python discovery passed 451 tests with seven skips. Inventory passed 120 failure families, 1,732
probes and 185 native suites; pinned formatting passed 1,618 Nim files and the Rust crate, and diff
checks pass. Lower preparation and store implementations are unchanged: their earlier algorithm,
root/entry, vector and failure evidence is reused instead of repeating identical checks.

Evidence remains under ignored `build/accumulation-block-publication/`. These are local macOS results,
separate from exact-head Linux CI and full JAM/STF parity. Next bounded work is source-bound
initial-round guest execution orchestration, connecting existing bound service/invocation/machine/
dispatch adapters to completed-round certification. Transfer-aware recursion, remaining account/
privilege effects and full block execution/validation remain open. M1 framing remains complete;
full state serialization and accumulation/block parity remain open.
