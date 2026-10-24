# Accumulation solicit host

## Current complete STF publication

The complete current STF path now applies bounded modified-account conflict and
account selection before publishing supervised effects. Independent signed
whole-map cases cover this host and selected panic/checkpoint behavior; see
[supervised conflicts](current-stf-supervised-conflicts.md) and
[the coordinated current status](graypaper-unreleased-upgrade.md#current-whole-map-accumulation-evidence).
The earlier host-only/legacy batch publication gates recorded below remain valid
for those narrower APIs, whose Unsupported ancestry guards are unchanged. They do
not describe the current complete STF path or establish full JAM wire parity.

## Current unreleased Gray Paper contract

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `pvm_invocations.tex`,
selects solicit as host 25. Register r7 selects an account (all ones means self).
Hash pointer and advertised request length occupy r8/r9. Lengths must be strictly
below 2^32-2; both reserved E4 values return HUH before memory/backend work. Public
effect APIs reject the same values as `InvalidLength`. Legal request keys stay separate
from storage/preimage namespaces.
Current self mutations preserve r8/r9 and accept explicit self or the sentinel.
Supervised target mutations now authenticate effective authority before namespace
hashing, use the target account's metadata/history/preimage keys, and retain the
invoking service's actual slot. Legacy self-only batch APIs retain Unsupported foreign ancestry. The complete STF
route uses bounded modified-account selection and selected-write proofs. The old
register layout is never accepted as an alternate production ABI.

Scope/completion: add nominal target overloads while preserving self APIs and
bounded self-key traces. Check length HUH before memory, then panic/WHO/authority
ordering, both account incarnations, target-only footprint/funding, immutable
checkpoints, typed backend/store failures, exact histories and ARC. Verify legacy batch refusal remains intact, current whole-map selection publishes
only selected foreign effects, and self tracing stays bounded.

The sections below preserve historical release implementation and verification records.


## Scope and authority

Implement solicit (24), Omega_S, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex solicit row,
definitions.tex CgasS=2193/bloblength=Nbits32 and accounts.tex footprint/deposits.
Charge before validation. Full-width r8 outside E4 returns HUH before memory;
otherwise capture 32 hash bytes at full-width r7. Unreadable memory panics,
retaining r7/r8. An absent current-self request becomes an empty requested history;
exactly two existing slots become three by appending the actual invocation slot.
All other existing shapes return HUH before funding. There is no age or chronology
check, and r8 remains unchanged for every row result.

A new request adds two footprint items and 81+length octets. Restoration leaves
footprint unchanged. Check the prospective exact deposit threshold, including
gratis and full-width products, against unchanged current balance; underfunding
returns FULL. Publish new history/metadata in one atomic two-write batch; a
restored history requires only one physical write after its funding check.
Counter overflow is a local InvalidState refusal, never wrapping or a guest code.
Malformed canonical history/metadata and hash/store failures remain typed local
refusals. Preserve preimages, storage, other accounts, allocation cursor,
transfers/provisions/yield and initial/exceptional versions. Borrowed buffers do
not enter published owners; the public operation uses nominal hash/length types.

Completion witnesses cover exact fee/deficit and ordering, all existing shapes,
new/restored history with current full-width slot, zero/max/full-width lengths,
exact footprint/funding thresholds and overflow, direct/host query and provide
consumers, repeated solicitation, preimage preservation, atomic backend/policy
refusals, retained nonempty effects/checkpoints, guarded API and ARC release.
Existing gates and pins remain unchanged, including the parked request namespace
question: preserve the pinned physical representation without fallback or interim
length restrictions. Next bounded host: forget (25).

## Local verification (2026-10-19)

Six focused native suites passed: solicit, query, provide, effects, dispatch and
outcome. Each retains fresh 1,000-cycle ARC evidence with unchanged occupied
memory. Solicit covers every history shape, exact funding/gratis thresholds and
full-width deposit products, two-limb funding, E4/E8 footprint overflow edges,
actual zero/default/max invocation slots, no chronology/expiry restriction,
zero/max/overlapping-prefix lengths, complete fee/deficit/length/memory ordering,
RO/cross-page hash input, unchanged balance/preimage/memory, current query and
provide, repeated and distinct-length requests, one-write restoration, two-write
creation, backend/policy refusal, retained nonempty effects and panic/OOG
checkpoint selection.

Both changed production modules passed standalone semantic compilation.
Thirty-seven runtime extraction refusals, two new nominal boundary rejections
and sixteen inventory/failure Python tests passed. Pinned parser metadata
confirms attached recordAccumulationSolicit documentation. Inventory, pinned
Nim/Rust formatting and whitespace checks passed. Evidence is under
`build/pvm-solicit/`: native.log, regression.log, guards.log,
targeted-results.json, semantic logs, inventory.log, Python logs and
format-check.log. These are local macOS results; complete verification and
exact-head Linux CI remain separate.

Efficiency: reuse of the current-history reader, exact deposit comparison and
private successor helper avoided repeating decoder/arithmetic/preservation work.
Restoration writes only its changed history. Prepared libraries and existing
drivers were reused, and the successful solicit suite was retained while running
affected consumers. No shared layout or fixture changed, so the full module
sweep and unchanged privacy probes were omitted. Existing gates and pins remain
unchanged. Next bounded host: forget (25).

## Supervised mutation verification

Local macOS solicit/forget, account-publication, bounded-self-write, storage-write,
supervisor, effects, dispatch, batch and accumulation-integration suites passed
with stable1000-cycle ARC evidence. The request suites release both self and
foreign successors. All264 production modules passed semantic compilation.
Compiler rejection guards and43 strict accumulation-effect result probes passed,
including both nominal target and failed-target extraction cases. The14 failure,
40 verification and14 request-namespace harness tests and inventory passed.

Foreign creation/restoration/removal uses target-only metadata, funding and preimage
namespaces, preserves invoker state, and remains an explicit parallel-publication
gate. Both sentinel/length/memory/WHO/HUH orders and immutable checkpoint selection
are covered. The real different-length solicit/forget roundtrip preserves an
available blob and restores its complete prior map with one traced request key.
These are local checks, not exact-head Linux CI, PolkaVM host-parity or complete
parallel/JAM parity. Evidence is under `build/supervised-requests-*` and
`build/tests/supervised-requests-guards/results.json`.
