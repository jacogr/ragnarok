# Resident service execution ownership

This implementation preserves the current pinned Gray Paper service classification,
initialization and execution behavior. It changes local code ownership, not protocol
outcomes. The complete-state `Services` owner retains one private, noncopyable
`ServiceExecutionContext` across its preparation jobs and dispatcher turns.

Four fixed slots retain existing `ExecutionWorker` values. Selection occurs only
after ordinary service lookup, full preimage hash verification and envelope/size
classification have certified Ready code for the current invocation. Keys contain
the nominal service index, complete code-preimage hash and selected backend.
Initialization still validates the envelope, exact encoded program and parse limits;
execution still checks the prepared engine's complete source/backend/cycle/resource
key. A hit never replaces missing, malformed, oversized or unauthenticated input.

An opaque noncopyable lease excludes every nested admission to the context before
initialization, including attempts inside synchronous host callbacks. It stays held
through immutable result publication and releases on scope exit, including typed
refusals. The worker handle is private. Every call receives fresh logical CPU, gas,
entry PC, arguments and host state.
Existing workers may retain a bounded immutable memory baseline and private scratch
for restoration; no live CPU/gas/host/callback/result/chain state persists. Failed
initialization marks retention ineligible while keeping the live lease's exact worker,
key and backend valid. Repeated failure remains typed; valid reinitialization in that
same exclusive scope restores eligibility. Only lease destruction retires an
unsuccessful entry, including adapter refusal before initialization. No failure
history survives release.

A miss prefers unused capacity, then evicts the fixed round-robin idle slot before
constructing its replacement. No fifth worker stages a miss. Invalid misses can
therefore evict useful resident code; subsequent protocol outcomes and retained
immutable outputs must remain unchanged. Four workers multiply the existing finite
per-worker code, fact, executable and memory limits. The optional default 64 MiB
idle-memory allowance is only one component; this is not an RSS bound. Only this
four-slot working set is resident. Evicted versions and replaced parse/
execution policies may need preparation again; services are not promised one
compilation forever. There is no negative cache, age history, new configuration
policy, global cache or new thread.

The actual current consumer carries the same context from `Services.beginPreparation`
through `PreparationWorker`, both direct and ancestor-completed `CurrentBlockInput`
paths, candidate completion, initial rounds and every current continuation. Supported
synchronous Services candidate/block-input calls and legacy initial/continuation/
reentry consumers carry it too. Standalone callers keep their existing one-shot or
explicit-worker entry points. No application refinement producer is claimed.

PreparationWorker publishes the context pointer alongside its existing borrowed
input/chain under the admission lock, before notification. The context and EVERY
input/chain/context alias, including read-only cache-info queries, remain untouched
by the host while Queued, Running or Done, including after cancellation. The
context's per-service busy flag alone does not grant full-job host access. Only exact
collection or joined close clears the pointer and returns ownership. Services joins
before retiring its context. `stopPreparation` and a worker restart preserve resident
code; full Services close/restart releases it. Idle occupancy observation obeys the
same host gate and exposes no mutable worker or allocation accounting. Keyed info
queries copy existing worker preparation/hit/resource observations; no duplicate
counters or mutable handles are introduced.

## Qualification checkpoint

All seven affected targets passed checked ARC release semantic validation on
macOS ARM64 with pinned Nimony. Actual checked ARC/Clang ThinLTO lowering and linking
passed for the pure context suite, initialized closed composite moves and the real
current-download consumer. Inspection verified explicit moved-from disarming,
eviction before replacement allocation, joined cleanup and exact collection before
borrow release. Supported local move declarations and actual Services defaults were
inspected. By-value/raising owner-return factories remain unqualified: the earlier
private probe emitted a guard read on an uninitialized result and is preserved as
static evidence, not a passed test or a compiler-bug claim.

Six registered native suites passed their complete Hastur goldens on macOS ARM64:
`pvm_service_residency`, `pvm_current_guest_runner`, `pvm_current_block_download`,
`application_preparation_worker`, `pvm_current_preparation_worker` and
`application_worker_ancestors`. The four registered ARC workloads each completed
1,000 cycles with unchanged occupied-memory baselines. Real observer libraries,
registered fixture hashes and fresh required ARC evidence were retained. These
observations cover those workloads, not a global leak-free guarantee or RSS bound.
Native Linux qualification and performance remain separate gates.

Tests specify A/B/A identities, fresh arguments/gas and retained outputs; repeated
failed initialization followed by valid reinitialization under one moved lease;
parse/backend policy changes, finite eviction, nested pre-initialization/callback
refusal, and original-source state preservation. Real guest classification tests
exercise missing, hash-mismatched, malformed and authenticated oversized code after
hits, with one-shot result/state parity. Existing current/legacy/ancestor workers
carry the context through cancellation, collection and restart. A real Services
witness adopts two signed children against changing parents, compares complete maps
against one-shot phase composition, checks different literal slot-dependent guest
yields and existing preparation/hit counters, preserves old immutable outputs, and
joins/restarts between blocks before full close retires the context. Positive
cache witnesses explicitly schedule authenticated code: the empty-child parent
grants service 42 an always-accumulate allowance, and direct/ancestor scenarios use
genuine execution fixtures. The original missing-code direct/ancestor cases retain
their zero-residency expectations, and the original reception fixture remains in
the 1,000-cycle ARC stress. Positive execution cases run separately from that loop.

Tests synchronize Done/collection, cancellation after Done and ancestor resumption.
Immediate cancellation/close stress uses actual threads but does not force every
Queued/Running interleaving. Shutdown during a specifically paused active guest or
host callback, exhaustive scheduling and TSan are not qualified here. Every host
alias must still obey the documented exclusive borrow contract. M1 completion
remains limited to its documented framing; full JAM/STF and complete state
serialization are separate gates.
