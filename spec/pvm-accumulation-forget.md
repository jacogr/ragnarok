# Accumulation forget host

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
