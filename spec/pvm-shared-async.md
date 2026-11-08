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
credits. These bound backing owners, not resident memory usage.
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

The compiler alone emits/maps/publishes code. Its mailbox receives only bounded POD IR and scalar
registration/ticket/stream epoch; no active ARC graph, registers, memory, host or callback. One
private Idle/Queued/Running slot holds work, while each registration owns its own completion and
exact scalar certificate. Publication immediately frees the work slot, so retained uncollected A
cannot alone block eligible B. Collection uses only the exact owner's row, independently of other
rows and work. There is no FIFO or general scheduling-fairness promise. Public NativePhase is an
aggregate observation: Queued/Running work wins, otherwise Done means parked Complete rows,
otherwise Idle. NativeRuntimeInfo.completions counts parked rows, including nil failed images.
Public Done is never an admission predicate. An exact matching consumer nonblockingly moves its
complete image only at invocation boundaries. Failed collection becomes Unavailable and does not
requeue until explicit stream invalidation. Same-plan destructive repricing invalidates the epoch
and cancels old jobs;
ordinary stream moves preserve identity. Installation rechecks every operation/operand against the
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
It leaves cleanup to the worker, with final drop marking Retiring so credit returns only after
physical destruction. Only an actual overlapping host-owned retirement violates the host contract.
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
across three further eligible calls. All native counters/occupancy remain zero; final owner drop
returns its credit before close/join. Normal profiles call the same maintained C constructor.
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

## ARM64 checked read bodies

The supported ARM64 JIT profile enables checked read admission on Linux and macOS.
The shared scheduler considers loop, then read, then pure work. In `executeWithHost`,
discovery requires a fresh handler stream and an uncharged first checked segment.
The probe restores the original terminal handlers before host callbacks. A successful checked
halt can nominate a candidate after 4,096 settled instructions. Admission requires
32,768 eligible visits and a measured source-work share of at least one eighth.
The probe tracks four candidates and attempts at most 128 walks of up to 32 source
facts each. A typed mailbox owns the copied request. A ready read body uses the
current invocation's checked memory extents and falls back to the original paid
handler when it cannot run.

The local production-shaped DOOM cohort showed a 14–20% CPU reduction for reused
ticks. Wall time was inconclusive. The earlier short-call cohort with a fresh worker
showed regressions whose cause remains open. Canonical Linux qualification is pending.

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
