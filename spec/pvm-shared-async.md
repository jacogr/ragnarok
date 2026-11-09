# Shared asynchronous pure spans

This increment changes optional local JIT ownership/scheduling, not GP0.8.0 gas, attempts,
PCs, memory, host calls, authentication or code decoding. Current source pin is recorded in
`spec/pins.json`. The per-registration completion runtime now has source/semantic checks and scoped
actual Darwin ARM lowering/execution qualification, detailed below. Each result retains its frozen
source, dependency and image identity; documentation-only integration does not relabel an old binary.
Actual canonical Linux qualification remains pending. No performance or complete-CI result is
claimed here. The maintainer explicitly accepts temporarily unported native features.

Both ISAs use one fixed copied IR, scalar source/node/epoch certificates, shared eligibility,
profit deferral, one-slot queue, four registration credits, native ownership, cancellation,
collection and entry bridge. Adapters reuse pure operation emitters and maintained OS arena/ABI
mechanics only. They contain no independent hotness, minimum-span, probe or retry policy.
The first supported item is one non-exiting pure register span per prepared identity, at most64
original source operations/coordinates and4096bytes of complete code. Each image uses the
maintained1MiB arena; installed, queued/running, parked and reclaiming owners consume the same four
credits. Deferred source identities and failed owners without images do not consume a credit.
These bound backing image owners, not checked prepared owners or resident memory usage.
This first slice does not claim the previous8192-fragment or connected/memory/macro coverage.
Unported features remain checked; they do not invoke legacy eager preparation to satisfy receipts.

`step.newNativeRuntime()` creates a code-independent stable anchor. `runtime.start()` explicitly
starts one compiler thread. It can raise on thread creation; unsupported platforms return false.
`runtime.close()` returns false while a public invocation has an active native lease, otherwise
cancels/joins without holding its lock. Repeated/default close is safe. The closed anchor and its
synchronization storage survive until all host-side session handles retire. A started last anchor
cannot be silently destroyed. Closed workers cannot restart while live registrations remain.
Host-side handle creation/drop retains the existing sequential/external-serialization contract;
the compiler never increments/decrements the host ARC anchor or touches a session/Program/Plan.
Copying/moving a host handle keeps its heap allocation stable. Initialized synchronization storage
cannot physically move, including after close; only the uninitialized storage sentinel can move.

`newPreparedProgram(source,limits,selected,nativeRuntime=default)`,
`newPreparedProgramCache(nativeRuntime=default)` and
`worker.newExecutionWorker(nativeRuntime=default)` bind the exact runtime at construction.
No runtime means checked execution even for requested Jit. There is no new CLI/JIT mode or hidden
per-Program worker. Program decoding/initialization, prepared-fact construction, input CPU/RAM
restoration and immutable result publication retain their normal APIs and real costs.
Services starts one runtime at full-state Jit startup, binds its context, joins preparation before
retiring context registrations, then closes/joins the compiler. `stopPreparation` alone preserves it.
Standalone callers must explicitly close their runtime; sessions may safely survive its closed anchor.

The [shared scheduler](../src/pvm/internal/native_pipeline.nim) owns the public
invocation lease, exact source epoch, image credit and nonblocking queue admission.
The lease excludes close even during checked execution without an image credit.

One shared initial policy requires a structural span of at least2supported operations, at least4096
conservatively completed nonterminal source instructions in ONE public invocation before scheduling,
and a4096-step current-call budget horizon before using ready code. Compilation eligibility retains
the maximum proven work of ONE completed public invocation bound to the exact source/stream epoch,
rather than the immediately preceding input or a cumulative sum. Epoch invalidation clears it.
These are unqualified rollout constants, not a measured break-even or candidate-specific hotness
estimate. Many tiny calls do not accumulate into a compile. Ready does not force native entry;
a later long same-source call remains eligible immediately after short inputs. A short call with a
large supplied budget can still use ready code: supplied budget is a coarse upper horizon, not a
prediction of current input work. Whole-invocation work may include checked
work unrelated to the chosen span, so this coarse bounded policy makes no profitability guarantee.

Only reason=None Halt/Host settled receipts are initially admitted. The original source-attempt
reservation is refunded first, then the attempted terminal instruction is excluded. Zero/partial
step limits, OOG, faults/panics and local failures contribute zero rather than speculative credit.
Host segments use their own rolling supplied/remainder budgets; one public lease sums their disjoint
receipts before callbacks can reset frame fields. Failed public calls never authorize compilation.
No opcode-level profiling, timer feedback, public work observer, fixture whitelist or ISA-specific
threshold is introduced. Paid/noop/host/error accounting needs the supporting literal witnesses.

The [worker and collector](../src/pvm/internal/native_pipeline.nim) own mailbox
isolation, registration-local publication and exact nonblocking collection. Public
`NativePhase` is an aggregate observation. Queued or Running work takes precedence,
then Done for parked completions, then Idle. `NativeRuntimeInfo.completions` includes
parked nil images. A failed collection becomes Unavailable until explicit stream
invalidation. Same-plan destructive repricing invalidates the epoch and cancels old
jobs. Ordinary stream moves preserve identity. Installation rechecks every operation/operand against the
current immutable source and validates existing node/continuation coordinates. An unchanged plan
pointer or node count alone is not a generation certificate. Native entry proves the original paid
full reservation and no partial barrier; the pure backend borrows only fresh registers. Invalid
post-native status is fatal, never replay after effects.

Last standalone prepared/session drop releases installed code before its credit, or marks an
in-flight owner Retiring until the worker really destroys its cancelled image. A single internal
retirement path detaches Complete/Installed images, marks Reclaiming, destroys outside the mutex,
then rechecks the exact saved row identity before returning its credit. Queued/Running cancellation
stays worker-owned even if stream invalidation cleared the session ticket. Close stops/broadcasts,
unlocks/joins, then detaches at most four parked images and destroys them outside the mutex.
Worker-owned Reclaiming is recognized by the still-Running global work slot and exact row key:
another serialized host invalidation or final drop may occur during its unlocked image disposal.
It leaves cleanup to the worker. Invalidation detaches the old session registration and marks
Retiring immediately, so the credit returns only after physical destruction; a new source epoch
cannot reuse an old pending key. Empty failed completions use this same exact retirement path and
release their credit while their retained source remains Unavailable without automatic retry.
Only an actual overlapping host-owned retirement violates the host contract.
Installed images remain in closed surviving sessions; those registrations prevent restart until
final drop. Registration has explicit noncopyable/move/destruction hooks; no owning row is copied
for observation or reset as an array. The compiler holds
no whole prepared/scratch owner and cancellation cannot free a live frame. A full registration/queue
is reversible checked fallback. Generation/ticket exhaustion refuses instead of wrapping. Native
compilation duration is explicitly unmeasured (`PreparedInfo.nativeCompilationMeasured=false`);
its numeric compatibility field is not a worker-CPU measurement.
`nativeFragments` counts successfully published images collected by that prepared owner;
an uncollected parked image is not included. `nativeCodeBytes` is current owned-image
occupancy; call/operation counters report actual completed native spans.

Primary performance is the canonical in-memory semantic-request-to-normal-usable-result bracket,
including all request-required constructor/decode/restore/runtime-start/publication work. A genuine
prestarted application runtime is an explicit separate lifecycle condition, never a hidden benchmark
preparation. The consume-before-reuse reference may expose its normal final-state borrow while this
engine returns its immutable Machine; full oracle scans are outside. No alternative benchmark route,
wait/sleep/readiness warmup/floor or old-row relabeling is introduced. Process CPU includes compiler
threads during its interval;13call-window sums are not owner-lifetime compute. A lifecycle total needs
its own enclosing interval and startup/drain/retirement accounting.

The two profile mains share the same literal tests: first AND second blocked-compiler calls return
checked; real ready image executes on supported hosts; tiny/reconsidered/closed calls stay truthful;
complete registers/gas/PC/RAM/history and settled budgets are checked. Host segments, queued final
drop/orphan credit, same-source stream epoch cancellation and independent source identity are covered.
Thirteen initially tiny calls remain deferred; subsequent long work schedules the retained candidate;
alternating ready long/tiny-budget calls must use native/checked paths respectively.
Ready-code tests also assert the exact partial4096-attempt register/gas/PC/RAM state, count only
the2730pure operations in1365complete triples, and reject native entry at an unpaid zero-gas header.
The barrier/wait hooks exist only under `pvmSharedAsyncWitness`, outside invocation clocks.

The new source tests add scalar one-shot AfterClaim, BeforePublish, AfterPublish and BeforeRetire
gates using the existing mutex/condition. Wait releases the mutex; stopping bypasses every gate without a
second controller thread. AfterClaim cancellation is reread before lowering. AfterPublish retains
the old LOCAL key because another owner may already queue new work in the global slot.
Gate release may atomically arm a distinct following point, so the host can pause the short
worker-owned Reclaiming window without a readiness race, polling or another controller thread.
Five schedule families cover retained A permitting B, four parked images blocking fifth/new-
generation admission, invalidation plus ticket-cleared final drop before lowering, cancellation
with a real worker-local image before publication, and close at queued/claimed/publish windows
with an installed survivor and restart. Distinct +3/+5 ADD_IMM_32 fixtures expose wrong-row image
swaps with full independent CPU/RAM/history checks. Immediate value changes neither opcode/alias
profile nor the approved22*(N+1) block-gas derivation; source attempts remain3*N+1. These are
unexecuted source tests for this increment, not a runtime, FIFO, or throughput claim.
The repair witness additionally repeats invalidate and final drop while the worker is paused
Reclaiming, both without an image and with a real local image. Four occupied credits deny a fifth
until physical disposal finishes; the freed generation then admits distinct +5 code while an
unrelated +3 completion remains usable. This targets the source-review finding missed by gates
that held only Running before cancellation; the original sealed source checkpoint is preserved.

The existing `pvm_runtime_policy_refused` profile additionally binds an eligible owner to the real
shared worker. On a supported selected ISA, the existing matching `pvmArm64JitRefuse` or
`pvmX86JitRefuse` define returns nil at the worker's arena-allocation boundary, preserving platform
capability and successful startup. Exactly one queued job finishes with an empty image; its owner
collects Unavailable, returns full literal checked CPU/gas/RAM/source/history, and never requeues
across three further eligible calls. All native counters/occupancy remain zero; exact empty
collection returns its credit before final owner drop. Normal profiles call the same maintained C constructor.
Unsupported hosts retain checked/start-refusal controls and are not allocation-refusal qualification.
This injection proves allocation refusal only, not publication failure or all resource-failure paths.

Registered coverage distinguishes the executed route. The ARM/x86 region-refusal frame orders,
ARM memory width/grouping matrix and ordinary x86 wide-source frames have no common session:
they preserve their full CPU/gas/deficit/PC/paid/register/RAM/permission/attempt/source/history
oracles through checked execution. The optional host-resume prefix retains its exact tiny budgets,
partial/paid/interior and host-resource checks without eager publication; the optional ARM
posterior-owner read keeps transactional host retry, fresh memory identities and old observations
without claiming native memory. Repeated tiny calls do not manufacture eligibility.

Direct legacy controls remain distinct and retain their actual positives: ARM macro arena/child/
resident capacity and fallback, ARM/x86 region shape/probe/real arena exhaustion/retained native
leaves, and x86 canonical/resident scalar/branch/RX-byte/six-register ABI checks. The x86 wide
main's pre-existing explicit parent-refusal hook creates an old JIT; that case is legacy governance,
not common allocation-refusal evidence, and zero child/parent calls alone do not establish refusal.
Ordinary unbound wide frames retain source-seal and owner-transfer proofs without the retired
pending table; its old sixteen-entry policy is not a common runtime contract. Source-interval
queries remain read-only structural authority controls. X86 checked-store selection/completion/
restored-stream receipts remain positive checked fusion controls, including native-refused absence.

The public runtime-policy, worker-application and host-memory-reference controls preserve truthful
unbound checked outcomes with all existing host/state histories. Actual common native positives
remain the explicitly runtime-bound pure-span main, including source-specific +3/+5 outputs,
worker gates, exact collection/cancellation, retirement/capacity, host resumes and closed-client
lifecycle. Actual allocation refusal uses its eligible bound worker job, distinct from unsupported
host fallback. Earlier binaries qualify only their own frozen source/platform/build profiles.

Native connected regions, mixed/grouped/read/dirty memory, wide children/parents and resident
macros remain unported to the common runtime. Each future port must prove eligible bound
submission and exact collection, real native entries with complete CPU/gas/attempt/RAM/host/
source/history oracles appropriate to the feature, and its owner/refusal/retirement/atomicity
boundaries. Pure arithmetic or legacy mechanical success cannot discharge these obligations.
No eager hook, invented activity counter or lowered work floor substitutes for that proof.


The canonical native-CI prerequisite keeps the old ISA witness route with two explicit scopes.
Raw C arena, literal emitter, clipped/typed ABI, real publication/capacity, memory-cycle and macro
backend positives retain their selected native/refusal policies and exact case cohorts. Bare
performance-witness frames retain every evaluator/single-step/literal CPU/gas/PC/paid/RAM/source/
owner/history cohort as checked execution. Their frame transfer, clipped, dirty/word, mixed,
cycle/resident and macro activity receipts report actual absence of native work, not allocation
refusal or an independent-native cross-check. ARM region order records use the checked FRAME
scope; x86 reuse records name checked stream reuse. Raw prefix rollback4/near-capacity1 and
embedded grouped/oversize kernel controls remain actual native proofs, not zeroed frame metrics.

Receipt validation retains exact case cohorts, raw mode-specific counts and rejection of missing,
duplicate, malformed or fabricated frame activity. Normal/resident-refused frame observables can
correctly match; no discriminator or feature flag is invented. Existing build variants remain
until their reached controls/source/semantic identity justifies reuse; append-refusal flags reach
actual raw macro publication and cannot be removed merely because frame images are absent.
A supported, explicitly bound common pipeline positive and real worker allocation-refusal gate
is separately required before overall native CI can pass. Legacy mechanical success and generic
unsupported-host goldens do not substitute for that behavioral proof. No tiny vector is inflated
to4096 work, repeated into eligibility or given an eager/native-job bypass for this migration.

Scoped local Darwin ARM qualification now includes actual supported bound common publication and
worker allocation refusal, the production Services lifecycle, the full normal legacy witness,
its four retained rejection/refusal variants, both ARM region receipt profiles, and seven affected
unit profiles with their complete existing goldens. Checked ARC/Clang release, bounds and ThinLTO,
actual generated C/imports, source/header/tool/image bindings, raw controls and complete checked
state histories were retained. The intentional legacy ABI rejection first proves both native
bridges, then rejects the same full-mode owner at its raw bridge guard before another native call.
These local results qualify their own reached controls; they do not establish a warmed JIT speedup.

Nine other mandatory controls remain locally unqualified: all-opcodes, regions-host, stream/frame
move and copy ownership controls, the C arena control, memory reuse and runtime policy. Their
execution remains required by the existing canonical native Linux ARM64 and x86-64 CI gates.
Explicit Linux/x86 semantics are source evidence; actual Linux x86 execution is still pending.
Unsupported-host goldens and ARM execution cannot qualify the x86 path.

The shared runtime and full-invocation comparison belong to one coherent source review unit.
The canonical producer records requested policy, real availability and actual native activity;
checked fallback for unported connected, memory, resident, wide and macro shapes remains visible.
The full-invocation adapters retain their real cold admission, RAM/CPU/host reset, public output
and independent post-clock validation boundaries. A historical local pilot stopped when a primary
process-CPU window was below clock resolution; its failure stays preserved without a floor,
discard, retiming or local benchmark retry. Actual two-architecture canonical Linux qualification
and performance reports on the final published source remain pending. No local or semantic result
here establishes complete CI qualification, full native feature coverage or a latency improvement.

## Shared scalar read bodies

Checked read admission supports Linux x86_64 and ARM64, and macOS ARM64.
The shared scheduler considers loop, then read, then pure work. In `executeWithHost`,
discovery requires a fresh handler stream and an uncharged first checked segment.
The probe restores the original terminal handlers before host callbacks. A successful checked
halt can nominate a candidate after 4,096 settled instructions. Admission requires
32,768 eligible visits and a measured source-work share of at least one eighth.
The probe tracks four candidates and attempts at most 128 walks of up to 32 source
facts each. A typed mailbox owns the copied request. A ready read body uses the
current invocation's checked memory extents and falls back to the original paid
handler when it cannot run.

The shared certificate admits all seven GP relative scalar loads: U8/S8/U16/S16/U32/S32/U64,
opcodes124–130. This ports the remaining S8/U16/S16/U32 forms to the common path. The same
`indirectMemoryAccess` table supplies each exact width. ARM reuses its existing typed encoding;
x86 adds four explicit load alternatives in the guarded emitter shared by resident and stack
transactions. Signed byte/halfword loads extend to64 bits. Unsigned halfword/word loads clear
every higher destination bit, including an old nonzero upper word. No evaluator or public API
is added.

The source certificate, nomination policy, worker ownership and limits remain unchanged.
Admission still needs2–8 reads in at most32 original facts; stores, direct loads and hosts are
excluded. The optional continuation remains three pure scalar operations. Every install/retry
reconstructs the original opcode, register slots, immediate, geometry and source epoch. Width
admission does not authorize a stale certificate. Adding eligible operations can change which
candidate wins despite identical thresholds; identical coverage or faster applications is not
implied.

The common72-byte memory context contains three clipped `(first, length, borrowed pointer)`
regions. Each load must fit its actual width within one current allocation and the interval
`[65536, 0xffffffff)`. Address formation wraps modulo2^32 before checking the extent. The
base is read before an aliased destination is overwritten; subsequent operations use the staged
current value. Any later guard refusal discards all speculative **register** writes before the
paid checked source body replays. This read-only body never stages a guest-memory write. The
legacy ARM144-byte raw/clipped context and its conservative eight-byte mechanical helpers
remain separate and unchanged.

`pvm_shared_read_widths_arm` and `pvm_shared_read_widths_x86` use the same independent
little-endian register literals, full CPU/RAM/permission/source oracles and real public prepared
owners. Each new opcode occurs twice in its genuine certified read block. The core body writes
three lanes; four additional immediate writes force x86's existing seven-destination stack
transaction. Correctness-only `AfterPublish` gates remain outside public invocations. Each ready
history requires the actual `CheckedReadBody` image,40,000 native calls,120,000 or280,000 original
body operations respectively, and no unrelated branch/header activity. An unsupported checked
fallback cannot produce the per-form native proof. These gates never enter application drivers
or performance readiness policy.

Mechanical cases cover sign/zero extension, aliases and a loaded-value address chain, positive
and negative wrapped displacements, unaligned accesses, empty/short/exact extents, clipped
pointer adjustment, upper endpoints and a new-form late refusal with all13 caller registers
checked before replay. Public histories cover changed input bytes, exact-width page tails and
their first invalid starts, missing/inaccessible late pages, repaired mapping reuse and retained
old snapshots. A separate genuine host7 callback replaces the map and reenters the same ready
read image; its one following visit must use the new bytes.

Frame witnesses retain complete partial snapshots and literal PCs/paid gas for all six boundaries
of the core five-fact block, exact/insufficient unpaid gas and a zero-gas paid interior attempt.
They independently reject changed opcode, destination, immediate and epoch certificates. The
public quota checks retain the4,096 invocation floor and the longer stack body's original
source attempts. The read block costs40 gas in both core and stack fixtures: its original
`UNLIKELY` latency dominates the independent reads/immediate writes. Four extra stack-body
instructions increase attempts from284,201 to444,201 for the complete guest, without changing
that block price. Expectations are literal; neither image metadata nor `blockGas` supplies them.

The native-host collector selects the registered matching ISA suite, seals its source/profile/
golden dependencies, removes any previous proof, and requires all eight distinct opcode/bank
records. Missing, duplicate, truncated, foreign-ISA, unrelated-image and zero-activity receipts
fail. The x86 mechanical ABI suite additionally exercises exactly six dirty lanes (all six
callee-saved GPRs) and seven dirty lanes through the maintained two-borrow sentinel wrapper.

Local ARM correctness is distinct from Linux qualification. Base `b3cc7564` includes the UI
platform fix from PR2038; the unchanged PVM source proof is retained in
`build/read-width-evidence/UI-INTEGRATION.json`. Real LinuxARM64 andx86_64 execution and
canonical enclosing performance comparisons remain pending. No timing result or performance
improvement is attributed to this capability port.

The earlier ARM-only local production-shaped DOOM cohort showed a 14–20% CPU reduction for reused
ticks. Wall time was inconclusive. The earlier short-call cohort with a fresh worker
showed regressions whose cause remains open. Canonical Linux qualification is pending.

## Retained qualified read nominations

A read certificate qualified by the bounded first-segment probe remains owned by its deferred
session when the compiler work slot is occupied. A later ordinary invocation restores the same
checked stream and reconstructs only the saved geometry, every original operation/operand and
the optional continuation. An exact source/epoch comparison permits retry; a mismatch explicitly
invalidates the stream epoch. This does not rescan a nonempty stream or discover another candidate.

Source validation is invocation-local. A short or failed call neither submits the retained read
nor replaces it with the weaker pure prefix. Retry still requires the existing successful-call
work floor, current invocation horizon and idle compiler work slot. A certified closed loop keeps
its existing higher priority. Submission fixes the request ABI and copied payload; pending and
ready jobs remain immutable. Epoch invalidation clears the deferred certificate. Close prevents
another invocation/submission, and a nomination-only source owns no image registration to return
or wait for. Queued/running read images retain normal cancellation and physical
retirement rules.

## Image-credit admission regression

The shared ARM/x86 lifecycle suite retains four independent sources, each making two calls that
settle3000 facts. Those calls cannot aggregate into the4096 proof or reserve image credits. A
fifth source settling6144 facts must queue through the real compiler and later enter native code,
with unchanged literal CPU/gas/RAM histories. Four real parked images still block a fifth until
physical retirement; the cancellation witness uses real parked filler images rather than cold
source registrations. The forced-allocation-refusal profile retains five Unavailable owners and
requires every next source to queue, while preserving no retry through explicit close/restart.
Independent controls cover a creditless active call refusing close, source-epoch invalidation
without registration and generation/ticket exhaustion without wrap or stranded credits.

`tests/models/pvm_native_credit_lease.nif` isolates lease versus credit ownership with the real
four-credit cap. Its original-admission variant exposes four cold registrations starving the
fifth eligible request. Guard mutants cover missing creditless close exclusion, premature credit
return before disposal, failed-empty-credit retention and a fifth image exceeding capacity; a
reachability witness requires actual fifth-source installation. Numeric work/gas and full
namespace/close windows remain source-confirmed by the native suite, not claims of the small
model. This is correctness/admission evidence, not timing or caller-wiring qualification.

The read arbitration suite covers occupied-slot retention, repeated restored-stream calls,
short/failed non-admission, loop precedence, retained optional continuations, source-epoch reset,
deferred close/drop and cancellation after a real read image has been lowered. Its supported
public path requires actual native read call/operation counts on each ISA; generic shared-span
positives alone do not qualify read retry. Existing partial/gas/fault and complete CPU/RAM/host
oracles remain. Local pinned checked ARC/Clang release qualification passes the maintained
selected arbitration runner on Mac ARM, including a fresh public proof of one image, 40,000 calls
and 120,000 completed read operations. The unchanged tiny-read, shared-async ARM and
allocation-refusal selected suites also pass. The final test source passes Linux x86-64 semantic
checking and the no-native public adapter passes default semantic checking.

An ignored public-only contention probe against archived master
`1eefb86b92b8e87e39cc07d0e0049590fbc88694` compiles with checked ARC/Clang ThinLTO and fails at
the intended short-call submission-count assertion. This is a runtime reproduction of lost read
selection, not a missing-helper compiler failure. Local selected runner flags retain their normal
non-LTO profile; these results do not qualify Linux execution or claim a speed improvement.
Exact-source Linux ARM64 and x86-64 qualification remains pending.
The [migration contract](pvm-async-migration.md) records broader applicable capability obligations.

## Shared admission and lease-release lock

`finishNativeInvocation` checks admission, clears unaccepted copied read nomination and releases
the active invocation lease under one mutex acquisition. The existing admission predicates,
request certificates, work thresholds and queue signal remain unchanged. Busy work or another
failed predicate can still defer admission; this does not introduce a readiness wait or a fairness
guarantee. Read-body POD cleanup remains before the active lease is released.

Scoped local qualification passes the unchanged shared ARM positive and allocation-refusal mains
with their complete goldens and fresh numeric proofs under checked ARC/Clang/ThinLTO. Actual
generated C confirms one acquire/release pair and POD cleanup before lease release. Mac ARM and
Linux x86 semantic checks pass; Linux runtime qualification and performance remain pending.
This architectural change does not establish the cause of the earlier shared-witness timeout.
