# Accumulation query host

## Current unreleased Gray Paper contract

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `pvm_invocations.tex`,
selects query as host 24. Register r7 selects an account (all ones means self).
Hash pointer and advertised request length occupy r8/r9. Lengths must be strictly
below 2^32-2; both reserved E4 values return HUH before memory/backend work. Public
effect APIs reject the same values as `InvalidLength`. Legal request keys stay separate
from storage/preimage namespaces.
Current query supports self and foreign-account reads. Missing and out-of-domain
services return WHO without truncation, after length/memory validation. WHO preserves
r8; successful query words retain the paper's exact packed shape.

The sections below preserve historical release implementation and verification records.


## Scope and authority

Implement query (23), Omega_Q, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex query row
and definitions.tex CgasQ=643/bloblength=Nbits32. Charge before row validation.
Full-width length r8 outside E4 returns HUH, preserving r8, before any memory
capture. Otherwise read 32 bytes at full-width r7; unreadable input panics with
both original registers. Look up only the invoking service's current request
map, at the exact hash and length; absence returns NONE/0, distinct from an
existing empty requested history (0/0).

Return copied fixed history fields: available => (1+2^32*x,0), unavailable =>
(2+2^32*x,y), restored => (3+2^32*x,y+2^32*z). Every slot retains its entire
unsigned E4 domain and exact position. No chronology sorting or age restriction
belongs to query. Bound history capture to thirteen bytes and reject malformed,
noncanonical, truncated or trailing records locally. Namespace hashing failures
remain local backend refusals. Do not alter accounts, effects, memory or
exceptional checkpoints. The public read API takes nominal hash/length types;
failed/default results contain only their reason, and absence is NotRequested.

Completion witnesses cover all history shapes and packed high-bit boundaries,
full-width length/pointer/gas edges, charged OOG/length/memory/absence ordering,
exact current-self namespace, zero/max lengths, retained owners/checkpoints,
missing/malformed records, inherited zero-write policy, backend refusal,
current-state interactions, guarded extraction, nominal boundaries and ARC release.
Existing gates and pins remain unchanged, including the parked request namespace
question: accept the pinned physical key representation without fallback or
interim length restrictions. Next bounded host: solicit (24).

## Local verification (2026-10-19)

Four focused native suites passed: query, effects, dispatch and outcome. All
retain fresh 1,000-cycle ARC evidence with unchanged occupied memory. Query
covers all four history shapes, zero/high-bit/max and deliberately unordered
slot positions, exact packed literal words, zero/max and overlapping-prefix
lengths, current-self isolation, absent versus empty requests, memory/length/
copy-policy precedence, exact fixed fee/deficit edges, full-width credit,
malformed/truncated/noncanonical/trailing records, namespace backend refusal,
zero inherited write capacity, unchanged state commitment and memory, retained
historical contexts, current physical backing after a storage mutation, yield
and panic/checkpoint selection.

Both changed production modules passed standalone semantic compilation.
Thirty-six runtime extraction refusals, two new nominal boundary rejections and
sixteen inventory/failure Python tests passed. Pinned parser metadata confirms
attached effectRequestHistory documentation. Inventory, pinned Nim/Rust
formatting and whitespace checks passed. Evidence is under `build/pvm-query/`:
native.log, regression.log, guards.log, targeted-results.json, semantic logs,
inventory.log, Python logs and format-check.log. These are local macOS results;
full verification and exact-head Linux CI remain separate.

Efficiency: prepared libraries and existing drivers were reused. No shared
layout, old mutation, fixture or privacy surface changed, so this tranche avoids
the full production-module sweep and unchanged privacy probes. One native build
was repeated after replacing aggregate commitment equality in a test with
explicit root-byte/count comparisons: nominal StateRoot has no implicit equality.
The successful query suite was retained while running its affected consumers.
Existing gates and pins remain unchanged. Next bounded host: solicit (24).
