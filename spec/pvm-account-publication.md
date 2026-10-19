# Terminal-selected self-metadata publication

## Scope and authority

This layer follows PR #190's integration witnesses on master b954efd. Authority is
Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex
`accpar` self-account projection and `accone`, with vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. No pins or protocol interpretation change.

Publish only the invoking service's selected metadata after genuine upgrade calls.
Retain common input/prior ownership, unique-service and slot proofs from the batch
coordinator. Track private immutable account-change scope through effect successors:
initial accounts, self-metadata-only upgrades, or unsupported broader mutations.
Yield and provide preserve scope; checkpoints retain the exact scope with their
account owner. Any other account mutation permanently marks that regular lineage
unsupported, even if later writes restore equal bytes or a subsequent upgrade runs.
This is a conservative proof of mutation scope, not an equality/root heuristic.

Every account mutation currently applies a nonempty store batch, creating a new
immutable version even for identical values. The private successor helper therefore
inherits scope only when retaining the exact account owner (yield/provide); every
new account owner defaults to unsupported, with upgrade the sole explicit opt-in.
All existing mutation call sites were checked against this invariant.

Normalize actual terminal outcomes before copying selected metadata. Never combine
regular metadata with exceptional scope. Copy each unique service's own full record
from its selected credited map; siblings' stale views cannot overwrite another
service's upgrade or incoming credit. Keep the existing account-write ceiling,
private fork, terminal provision integration and single publication point. No new
whole-map diff, generic merger or mutable snapshot exposure is introduced.

Broader storage/request mutations, creation/deletion, outgoing transfers (including
zero value), privilege/queue/staging changes remain UnsupportedAccountEffects.
Grow_heap remains UnsupportedHostCall. Recursive transfers and other recorded GP
gates stay unchanged. M1 framing is complete; full serialization, complete accpar,
Psi_A and whole-block publication are not claimed.

## Completion tests

Execute genuine upgrades with two services, incoming credits, multiple upgrades,
halt and checkpoint/panic selection. Compare exact metadata and independently
constructed full-map roots, preserving unrelated chapters, storage and code.
Exercise provide after upgrade, stale publication, account budgets, late backend
refusal, detached owners, broader-mutation then upgrade, and retained zero-transfer
refusal. Run a fresh 1,000-cycle ARC preparation/application workload. Verify the
new read-only scope API's default refusal, private owner protection and guarded
result extraction using the existing effects contracts. Reuse unchanged fixtures
and parent evidence; run affected native consumers and guards only.

Next bounded work: self-storage/request write provenance and bounded disjoint
publication, before cross-service creation/deletion conflict rules.

## Local verification (2026-10-19)

Seven native suites passed: pvm_account_publication,
pvm_accumulation_integration, accumulation_batch, accumulation_complete_batch,
accumulation_effects, pvm_accumulation_upgrade and pvm_accumulation_outcome.
All retained fresh 1,000-cycle ARC evidence with equal occupied memory before/after;
the new execution/preparation/publication workload stayed at 170,000 bytes.
Exact roots cover two upgraded services, independent incoming credits, unrelated
entries, execution permutations, checkpoints and combined provision fulfillment.
Early and late backend refusals preserve the exact original publication owner.

Four downstream modules passed semantic compilation: accumulation_execution,
accumulation_outputs, accumulation_continuation_execution and
accumulation_reentry_execution. Their unrelated native Bandersnatch dependencies
were not rebuilt. Thirty effects and fifteen batch extraction guards passed,
including the new default scope guard, with ten effects/batch privacy rejections.
Pinned parser metadata confirms five attached API docs. Sixteen failure/inventory
Python tests, source-owned inventory, pinned Nim/Rust formatting and whitespace
checks passed. Native bridges and vendor pins are unchanged. These are local
macOS checks; exact-head Linux CI remains separate.

Evidence is under `build/pvm-account-publication/`: regression.log, guards.log,
guards-results.json, four semantic logs, python-selected.log, inventory.log and
format-check.log. A short incoming-credit budget still refuses before provision
hashing; the existing regression caught that ordering requirement while terminal
selection was moved ahead of metadata copying, and the minimum-write preflight
was restored before the final passing runs.

Efficiency: the immutable scope observation avoids full-map scans, a new diff API
and copied write journals. Existing guest framing, batch fixtures, prepared native
libraries and guard drivers were reused. Two early fixture compile retries exposed
mutable global inputs and an explicitly initialized fixed-array result required by
the pinned compiler. Final checks cover affected consumers; no dependency setup or
unrelated suite/whole-source sweep was repeated. PR #190 remains the unchanged
parent, with this layer registered through the native stack workflow.

## Bounded self-entry extension

[Self account writes](pvm-self-account-writes.md) adds explicitly bounded key provenance
for storage, solicit and forget. It preserves this layer's upgrade support and keeps
zero-policy callers on the original conservative publication boundary. Creation/deletion,
outgoing transfers, privilege changes and grow_heap remain gated.
