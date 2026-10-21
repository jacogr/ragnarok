# Accumulation storage write host

## Current unreleased Gray Paper contract

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `pvm_invocations.tex`,
selects write as host 5. Register r7 selects an account (all ones means self).
Key pointer/length and value pointer/length occupy r8-r11. Current self writes
accept the sentinel or explicit self ID. Foreign supervised mutations remain a typed
`UnsupportedHostCall` implementation gate. Dynamic fees use the current length registers.

The sections below preserve historical release implementation and verification records.


## Scope and authority

Implement write (5), Omega_W, against GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, pvm_invocations.tex and
accounts.tex footprint/threshold equations. Cost is
`2442 + ceil(3358*r8/1024) + ceil(216*r10/1024)` before all row mutations.
Read key r7/r8 and value r9/r10; zero value length deletes without reading r9.
Return previous value length or NONE on success, FULL if the candidate threshold
exceeds balance. Update canonical self metadata and storage atomically on a
private complete map. Footprint deltas include 34+key length+value length and one
item for insertion/deletion. Never wrap footprint or deposit arithmetic.

Current account snapshots belong to each immutable implication version. Reads,
lookup and provide consult the regular snapshot. Checkpoint retains that snapshot;
normalization selects regular on halt and exceptional on panic/OOG. Initial
provenance remains separately immutable. Local copy/store/backend refusals expose
no partial machine or effects; guest panic/FULL retain the previous snapshot.

Completion witnesses cover insert/replace/delete/absent-delete and empty keys,
old lengths, read-after-write, exact deposit/gratis boundaries and wide arithmetic,
full-width gas and signed debt, memory/gas ordering, local/store/backend refusal,
metadata preservation, checkpoint rollback, original owners and ARC release.
Other mutation hosts and persistent block publication remain later increments.

## Arithmetic, ownership and refusal boundaries

The existing read gas helper now selects the exact read/write register layout and
constants. Bounded base-2^32 limbs retain the complete cost; independently rounded
value gas is added without losing a carry. Debt through 2^63 is exact, while larger
debt retains the existing GasRangeExceeded local gate.

Deposit comparison uses the equivalent `base + itemRate*items + byteRate*octets
<= balance + gratis`. The right side may require 65 bits. Each exact 128-bit
product is compared and subtracted from that budget, so neither overflow nor
saturation can turn an underfunded account into an accepted one. Candidate E4/E8
footprint overflow is a local InvalidState refusal; inconsistent old counters
refuse as MalformedState. The counters are serialized account facts updated by
an exact delta, not a full reverse reconstruction of hashed storage namespaces.

The regular effect retains a new complete-map owner only after inherited store
limits, metadata serialization and Merklization succeed for the atomic two-write
batch. FULL, guest memory panic and all local failures retain prior versions.
Absent deletion still checks the candidate threshold. A preexisting present-empty
value reports old length zero and is removed by a zero-length write. Other account
metadata, provisions and yield are preserved. Initial invocation/account provenance
stays historical; callers use effectAccounts for current/post-execution state.

No complete-state publication or account mutation outside this self-storage row
is added. Info (6), grow_heap and remaining accumulation operations are subsequent
bounded work; full Psi_A and the existing provision/hash-return gate remain open.

## Local verification (2026-10-19)

Nine affected native suites passed: write, effects, read, lookup, provide, dispatch,
outcome, provision integration and PVM machine initialization. Each recorded fresh
1,000-cycle ARC evidence with unchanged occupied memory. The new write suite
covers exact gas/deposit boundaries, 65-bit balance-plus-gratis, cost-limb carry,
2^63 debt versus local refusal, namespace and later Merklization failure, malformed
and overflowing counters, present-empty deletion, read-after-write, independent
owners, and checkpoint selection on panic and later host OOG.

All 111 production modules passed semantic checks. Twenty-one runtime result
probes (including current-account and failed-storage extraction), nine privacy
rejections and 42 selected discovery/failure/native-harness Python tests passed.
Inventory, pinned Nim/Rust formatting and whitespace checks passed. A broader
unchanged context/admission suite was not executed locally: its separate
Bandersnatch fixture profile is outside the changed PVM helper consumers.

Evidence is under `build/pvm-write/`: native.log, native-results.json, guards.log,
targeted-results.json, modules.log, selected Python logs and format-check.log.
This is local macOS evidence, not complete verification or exact-head Linux CI.
Native consumer runs shared one prepared crypto library set rather than repeating
provider preparation; all per-suite execution/output/ARC checks remained fresh.
