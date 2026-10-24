# Accumulation forget host

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
selects forget as host 26. Register r7 selects an account (all ones means self).
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
Current Omega_F explicitly removes only the request for an empty history. An expired
two-slot history removes both request and preimage. This resolves the historical
unbound-y wording below; current production follows the distinct row updates,
including preservation of a stored preimage in an authored empty-request map.
The historical full-E4 vector witness is now a rejected length. Its public hash and
slot also seed a separate authored maximum-legal-length boundary case; this is not
claimed as unchanged current parity with that historical vector.

The sections below preserve historical release implementation and verification records.

A reachable regression starts with hash h available at actual length3. A guest then
solicits `(h,4)` and forgets that empty extra request. Only the `(h,4)` reservation
is removed: `(h,3)`, its available history and the three-byte preimage remain. The
native two-host witness restores the complete original map, releases the reservation of two
items and85 bytes, and fits one bounded request-key trace slot. Expired two-slot
forgetting still removes request and preimage under a three-write store policy.


## Scope and authority

Implement forget (25), Omega_F, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex forget row,
definitions.tex CgasF=3250 and accounts.tex footprints. Charge before validating
full-width length r8; invalid E4 length returns HUH before memory. Otherwise
capture the 32-byte hash at full-width r7; memory panic retains both inputs.
Absent history returns HUH. Existing histories transition as follows:

- Requested []: remove request and any retained preimage immediately.
- Available [x]: become unavailable [x,t], retaining footprint/preimage.
- Unavailable [x,y]: remove request/preimage only when y+expungePeriod<t.
- Reavailable [x,y,w]: become unavailable [w,t] only when y+expungePeriod<t.

Use the actual invocation slot and widened strict expiry comparison with
expungePeriod=maxLookupAnchorAge+4800; nonpositive mathematical cutoffs never
wrap. There is no funding check or balance debit. Removal subtracts exactly two
items and 81+length octets, with inconsistent counters rejected locally. History
replacement leaves metadata unchanged and needs one write. Removal publishes
metadata/request/preimage changes atomically in at most three writes, deleting
an equal pinned request/preimage key only once. All row returns preserve r8.
Preserve other accounts, preimages/storage, cursor, retained effects and initial/
exceptional versions. Malformed state, hashing/store refusal and resource policy
remain typed local failures; public hash/length domains remain nominal.

## Empty-history text discrepancy and pinned witness

The GP deletion branch includes [] and [x,y] under a condition involving y,
which is undefined for []. Pinned vectors revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`, accumulate README and
`stf/accumulate/tiny/preimage_len_bound-3.json`, resolve this empty case: service
0's empty request (hash 943e3d42cf248c99fa6346c24b66741090bd2c78f9ff691c5fd7a88ef51d27e2,
length 4294967295) is present at pre-state slot 44 and absent after input slot 45.
The native suite projects this exact service/hash/length/slot witness through
our authored guest, without claiming whole-STF or instruction-gas parity.
Adopt immediate deletion for empty requests; do not invent a timestamp or add
a new gate for behavior resolved by the pinned evidence. Sources remain pinned.

Completion witnesses cover all history branches, exact expiry/gas/deficit edges,
full-width values, zero/max and overlapping-prefix lengths, bounded capture,
malformed histories/counters, unfunded callers, preimage preservation/removal,
current query/solicit/provide consumers, repeated forget, atomic backend/policy
refusals, retained owners/checkpoints, guarded API and fresh ARC release.
Existing gates remain unchanged. Next bounded work: accumulation host integration
coverage and remaining-gate audit.

## Local verification (2026-10-19)

Eight focused native suites passed: forget, solicit, query, provide, effects,
dispatch, outcome and accumulation machine. Every suite retains fresh
1,000-cycle ARC release evidence with unchanged occupied memory. Forget covers
the exact pinned service-0/hash/max-length/slot-45 empty-removal projection,
all history transitions, strict expiry boundaries and widened anchor arithmetic,
zero/max slots and lengths, shared physical namespace deletion, exact footprint
subtraction and inconsistent counters, unchanged preimages/balance/memory where
required, unfunded callers, exact fee/deficit and row ordering, current query/
solicit/provide consumers, repeat deletion, atomic early/late hashing and write
policy refusal, nonempty retained effects and panic/OOG checkpoint selection.

Both changed production modules passed standalone semantic compilation.
Thirty-eight runtime extraction refusals, two new nominal rejections and sixteen
inventory/failure Python tests passed. Pinned parser metadata confirms attached
documentation for recordAccumulationForget and the fixture's optional nominal
service selector. Inventory, pinned Nim/Rust formatting and whitespace checks
passed. Evidence is under `build/pvm-forget/`: native.log, regression.log,
guards.log, targeted-results.json, semantic logs, inventory.log, Python logs,
format-check.log and vector-witness.json. The pinned source JSON was retrieved
without changing its gitlink. These are local macOS results and a native
projection; complete verification and exact-head Linux/whole-STF parity remain
separate.

Efficiency: the targeted pinned README/vector inspection resolved the empty-case
text issue without a speculative new gate. Reused current-history, successor,
fixture and prepared-library paths avoided rebuilding those components. Extra
focused builds came from runtime-let default inference, unsupported sequence
concatenation and a wrong unchanged-r8 expectation in test helpers; use typed
default accessors, explicit byte appends and exact supplied register values in
future witnesses. The final passing forget run was retained while checking its
affected consumers; no full module sweep or unchanged privacy probes were run.
Existing gates and pins remain unchanged. Next bounded work: accumulation host
integration coverage and remaining-gate audit.

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
