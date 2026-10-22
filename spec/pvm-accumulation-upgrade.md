# Accumulation upgrade host

## Current unreleased pin

The [coordinated upgrade](graypaper-unreleased-upgrade.md) targets
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. Current upgrade is selector21:
r7 selects the account (all ones means self), r8 points to the hash, r9/r10 carry
the minimum accumulation/transfer gas. The self path preserves supervisor fields
and current account-write proofs. Authorized foreign mutation now executes against
the retained invocation map, while parallel batch publication remains explicitly gated. Underfunding drains gas to zero. The details and verification
below retain the historical release argument layout.

## Supervised target execution

Scope: the same current Omega_U row permits the invoking service to upgrade itself
or an account for which it is the effective supervisor. The state operation accepts
an explicit nominal target, checks current canonical target/invoker metadata and the
supervisor creation slot, then replaces exactly the code hash and two gas fields in
one atomic store successor. Self remains legal even when another service supervises it.
The existing self-only API delegates to the same checked implementation.

Foreign metadata marks account ancestry `Unsupported`; later self writes cannot
reset it. This is an execution capability, not a claim of parallel publication:
`accpar` requires modified-account conflict selection before foreign effects can be
merged. Retain the batch gate until that selection and its provenance are implemented.
No complete state or block parity is claimed.

Completion: upgrade/effects/dispatch and publication consumers; foreign success,
stale/missing authority, immutable prior/checkpoints, repeated changes, wide gas,
atomic backend/policy refusal and stable ARC. Existing WHO/HUH/panic/gas order stays fixed.

Local macOS upgrade/effects/dispatch/account-publication/batch suites passed with
stable1000-cycle ARC evidence. All264 production modules, compiler rejection guards
and39 strict accumulation-effect runtime guards passed. A genuine common-source
fixture proves the foreign upgrade executes while batch preparation refuses its
unsupported account provenance and leaves the source root unchanged. This is local
evidence, not exact-head Linux CI or complete parallel accumulation parity.

## Current foreign-target refusal ordering

Scope: Omega_U at Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex`, current upgrade21. Charge1028 first, then capture the entire
32-byte hash before selecting the account. A full-width missing or out-of-domain
selector returns WHO; an existing foreign account whose effective supervisor is not
the invoker returns HUH. Supervisor authority includes the recorded creation slot,
so a recreated service cannot inherit it. These protocol refusals precede the
authorized foreign mutation. Self/sentinel success
and all publication boundaries remain unchanged.

Completion checks: native `pvm_accumulation_upgrade` and dispatch consumers, covering
fault versus missing/unauthorized targets, exact/short gas, full-width IDs, malformed
metadata, stale supervisor incarnation, unchanged accounts/checkpoints and retained
ARC ownership. This closes an implementation error, not a discrepancy in the paper.

Local macOS upgrade and dispatch native suites passed, each with stable1000-cycle
ARC evidence. This earlier refusal-order tranche left authorized foreign mutation gated; the
supervised execution section above describes its subsequent implementation.

## Scope and authority

Implement upgrade (20), Omega_U, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex upgrade row
and definitions.tex CgasU=1028. Charge 1028 before reading the complete raw
32-byte hash at full-width r7. Invalid input panics, preserving r7 and effects.
Success returns OK, replacing only the caller's code hash, minimum accumulation
gas r8 and minimum transfer gas r9. Preserve every bit of both uint64 gas fields.
No privilege, funding, code-availability or request mutation check is introduced.

Publish C(255,self) on a fork of the current complete account map, with all other
metadata fields and mappings unchanged. Preserve the current allocation cursor,
queues, staging, privileges, provisions, yield and exceptional checkpoint. Initial
provenance and the currently executing program retain the original code; upgrade
does not restart the invocation or require the offered code's preimage to exist.
Local memory-copy/store/backend refusals expose no partial execution or successor.
The state API accepts nominal copied hash/gas values and derives self from the
prepared invocation; callers cannot substitute a target account.

Completion witnesses cover exact gas/debt boundaries, full-width pointers/hash/gas,
RO and cross-page inputs, atomic current metadata, unchanged fields/mappings and
prior owners, current info, repeated upgrades, preservation through later effects,
new-service cursors and children, retained yield/provisions, panic/OOG checkpoints,
store/backend refusal, guarded API extraction and ARC release.

## Boundaries and verification scope

Existing heap, conflicting bless allowances, request namespace, signed-gas and
provision normalization gates remain unchanged. No pins or persistent state
publication change. Remaining accumulation hosts stay explicit adapter gates;
transfer (21) is next.

This tranche adds no shared state field or error alternative and changes no
fixture contract. Focus native verification on upgrade and the current-account,
creation, dispatch and outcome consumers. Existing prepared native libraries and
verification drivers remain reusable with fresh per-suite output/ARC evidence.

## Local verification (2026-10-19)

Seven focused native suites passed: upgrade, effects, new, write, info, dispatch
and outcome. Every suite retained fresh 1,000-cycle ARC evidence with unchanged
occupied memory. Upgrade witnesses cover exact gas/deficit edges, full-width
credit/pointers/minimum gas, zero hashes, readable RO/cross-page inputs, capture
limits, unprivileged and unfunded callers, exact typed/serialized fields with all
other metadata preserved, unchanged unrelated accounts/original code preimage,
current info and continued original execution, repeated replacement, storage/yield
and new-service interactions, retained provision/yield owners, allocation cursors,
panic/OOG checkpoints, store policy and immediate/delayed hashing refusal.

The two changed production modules passed standalone semantic compilation.
Twenty-six runtime extraction refusals, six privacy rejections, two nominal hash
rejections and eleven selected inventory/failure Python tests passed. Pinned
parser metadata confirms attached documentation for recordAccumulationUpgrade.
Inventory, pinned Nim/Rust formatting and whitespace checks passed.

Evidence is retained under `build/pvm-upgrade/`: native.log, guards.log,
targeted-results.json, effects-semantic.log, dispatch-semantic.log, selected
Python logs, inventory.log and format-check.log. These are focused local macOS
results; full verification and exact-head Linux CI remain separate. Scope-based
selection avoided repeating the entire production-module group and unrelated
host/fixture suites. Prepared libraries and the existing native driver were
reused with fresh execution/output/ARC checks.

Checkpoint witnesses use their own invocation metadata because each authored
program has its own initial code hash. Existing fixture and shared-type contracts
remain unchanged. Next bounded host: transfer (21).

## Self-metadata publication extension

[Terminal-selected batch publication](pvm-account-publication.md) now supports proven upgrade-only self-metadata lineages. This extends the original invocation-local scope; broader account mutations and grow_heap remain gated.
