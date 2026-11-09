<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PVM CI performance monitoring

## One current-source comparison

**Perf / PVM** runs on native Linux ARM64 (`ubuntu-26.04-arm`) and x86-64
(`ubuntu-26.04`) on every master push, manual `perf`/`full` request and open-PR
`ci:perf`/`ci:full` request. Ordinary PR updates run Smoke only. Both architecture
jobs use `make bench-pvm-performance` and the same runner, workload inventory and
versioned report. Storage performance is independent. New master pushes retain
CI's existing cancellation policy, superseding unfinished older revisions.

The manual `bench-pvm` scope runs the complete PVM cohort without Storage or
unrelated CI groups. `bench-doom` selects its DOOM subset. Both default to the two
architectures; `pvm_architecture` can select one native CPU for these focused
requests. Partial reports identify their scope and cannot satisfy complete
master-report retrieval. Native CI diagnostics may select `PVM_PERF_SCOPE=micro`
through the same Make target. Profiling, calibration, retained-core, replay and
historical pricing/revision tools remain explicit Make diagnostics, outside this
CI measurement path. Their former `jit-*` CI dispatch choices and optional previous
baseline inputs are retired.

## Workloads and engines

The complete inventory composes the maintained eleven synthetic micro workloads,
sieve at 1k/10k/100k/10 million, minimal and memory fill at 1k/100k, one initialized
Pinky frame, and separate DOOM initialization/gameplay calls. The three engines are
current public prepared execution with forced interpreted policy, the same current
production image with JIT policy, and pinned PolkaVM interpreted. Native compiler
and reference source pins are unchanged. No standalone native backend, historical
baseline or retained-core timing substitutes for a current public call.

The synthetic harness records genuine process CPU and wall nanoseconds. Historical
wall-only observations are never relabeled CPU. All native policies use production
architecture flags and the checked ARC/Clang ThinLTO profile; native-host
qualification must pass before timing. The declared runner, actual uname/Python
architecture, native compiler archive and measured source must agree.

DOOM uses the canonical 1,320-tick prepared gameplay state and upstream rendered-frame
golden, with independent initialization and tick fixtures. The warmup count, guest,
WAD, expected state and event hashes identify this cohort. Historical warmup-zero
comparison results are a different workload. Complete CPU, gas, PC, paid state,
registers, final page layout/permissions/bytes, source snapshots and ordered host
output are checked outside clocks. Assertion/state/event refusal controls and
source/fixture identity checks remain required. Expected results are never generated
by the measured candidate.

## Measurement and reporting

The current `pvm-performance-v3` cohort binds `full-invocation-v1`,
`code_lifetime=retained-code-v1`, `program-state-host-inputs-v1`,
`consume-before-reuse-v1` and the real process CPU clock. Each process begins with
`PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu`.
A scope receipt is required by the canonical producer parser; older clock records
cannot qualify merely by changing a report's schema or labels.

The cold request starts from already-read program bytes, declared CPU/RAM and
host inputs. Its actual encompassing CPU/wall clock starts before code-specific
decode, Program/Module validation, memory capture, prepared-owner and instance
creation. No decoded Program, Module, prepared owner, RawInstance or dummy clock
instance is created before that boundary. Resident requests may reuse the actual
admitted code owner and immutable baseline. Their encompassing clocks start before
invocation-specific RAM/CPU restoration, host progress reset and collector setup.
All normal dispatch, host input delivery, owned event-payload capture and final
public output publication occur before either enclosing clock stops.

Both engines expose the final outcome, CPU state and public final-memory owner/view
until the consumer finishes before the next reset. Ragnarok's normal immutable
publication is included. PolkaVM's ordinary public instance view is consumed without
an artificial full-RAM freeze or copy. Complete independent state/page/event scans,
comparison and serialization occur after the clock. Fixture/container IO, fixture
creation and independent oracle preparation are external to the request. Pinky's
initialized frame and DOOM's state after 1,320 fixture ticks are frozen inputs; the
measured retained owner is never rehearsed to recreate those inputs. Reset/write
APIs and input geometry are checked normally; the performance path does not repeat
an independent whole-RAM pre-input scan inside the primary window. Complete final
state and refusal controls remain mandatory.
Ordinary guest reset reuses the module's declared immutable initial RAM, whose
compatibility is established by the frozen-fixture producer. Initialized Pinky
and DOOM writable snapshots override that baseline through normal write APIs.
Canonical Ragnarok non-Pinky guests receive the same compact artifact through
`RAGNAROK_PVM_SIEVE_ARTIFACT` and admit it with production `decodeArtifact` inside
the cold clock. The frozen invocation still supplies all thirteen registers, gas
and entry; artifact entry lookup must match `run_checked`, and its page limit is
the invocation's exact mapped-page count. The expanded snapshot remains the
independent post-clock oracle for exact initial code, page identities, permissions,
bytes and page ceiling. Pinky retains its complete initialized snapshot admission.
Historical execution-only adapters keep their explicit snapshot input path.
Both admission paths use the same 4 MiB program-byte ceiling. Artifact admission's
jump ceiling is its 4 MiB code-byte limit rather than the snapshot path's 1 Mi
entries; frozen sieve/minimal/memset declare only 148/4/11 entries respectively.
Artifact format, symbol and export validation remain normal production work.
Ordinary guest code/jump-table bytes are compared exactly against the admitted raw
module source after sample0, including unreachable instructions. The raw source is
retained with an immutable shared byte handle created inside cold admission; no
extra decode or code owner is warmed before the clock.
Independent read-only input compatibility checks run after sample0's clock,
while read-only state is still unchanged, before accepting any observation.

The standalone production JIT process starts one application-owned compiler
runtime and waits for its worker to enter the idle mailbox loop before the first
cold request. The synthetic process shares that runtime across all eleven code
owners. Each selected guest or DOOM process currently has one code owner.
Guest-specific admission stays inside the cold clock.

The forced-interpreted process uses the default runtime handle and creates no
compiler thread or synchronization owner. It emits `PVM_RUNTIME_NONE` with reason
`interpreted-policy` and its code-owner count. The JIT process reports
`prestarted` creation in `PVM_RUNTIME_OWNER` alongside ownership and code-owner
count. The report binds that receipt to `identity.measurement.jit_runtime_start`.
Historical full-invocation reports with `demand-started` receipts include startup
in the first JIT call of each process.

Closing and joining follow the final output consumption. `PVM_RUNTIME_CLOSE`
records the closing CPU and wall deltas. `PVM_OWNER_WINDOW`, marked
`includes-driver-oracles`, includes startup, close and driver work for JIT.
The interpreted owner window includes its actual prepared-owner retirement.
Keep these process windows as separate diagnostics with their own granularity.
Reference instance and module teardown occurs before its owner-window observation.
Native compiler clock availability is explicit in `PVM_NATIVE_COMPILATION`; an
unmeasured accounting zero never becomes worker CPU or a measured zero duration.
Any duplicated raw compilation accounting is type-checked and must equal its scope
receipt. Full guest/DOOM owner receipts read their first five counters from the same
common preparedInfo API as runtime policy, rather than legacy ARM caches. Current
shared pure-only images have zero guest-branch/header counts. Positive owned code
bytes require a collected image; cumulative collected/native-work counts may stay
positive after current owned bytes return to zero.


Each process emits thirteen raw validated calls. Sample0 is the cold call;
samples1–12 are resident. Reused statistics use exactly samples3–12, independently
for CPU/wall and both unchanged process orders. No sample is filtered for native
readiness, no hidden warmup/wait is introduced and no minimum native work or
profitability threshold is imposed by Perf. Incomplete shared async coverage and
checked fallback remain valid observations. Requested policy, availability and
actual counters must agree; native capability correctness is qualified separately.
The first invocation runs checked. After worker startup, invocations use checked execution
while any generated code they need is pending.

Primary CPU is process CPU including all in-process threads. Worker/thread and
lifecycle observations remain diagnostics; none is added to or subtracted from
primary CPU. Sum/prefix tables use the thirteen actual enclosing windows, including
samples1/2 and delayed costs. They are not owner-lifetime totals: an async worker can
run between windows. The first observed JIT/interpreted break-even call includes
equality, may reverse, and predicts no future crossover. Reuse count is call count
minus one. A crossing can remain unobserved. Historical demand startup could itself
cost more than interpretation. Pending compilation can still contribute process CPU
when it overlaps a measured invocation.

Reference receipts are clock-free version2:
`REFERENCE_INSTANCE,2,label,0`, thirteen ordered
`REFERENCE_CACHE,2,label,sample,before_reset,after_reset,after_run`, and
`REFERENCE_INSTANCE_DROP,2,label`. There is one actual interpreter instance per
case, initially empty, whose lowered-code cache survives every public reset. Cache
sizes must remain continuous and nonshrinking, and become positive after execution.
Unavailable constructor/restore/drop clocks remain absent. Optional genuine nested
constructor clocks stay in diagnostics and are not separately charged to the
already-enclosing cold call. These optional nested clocks may genuinely resolve to
zero; full-mode parsing/reporting preserves nonnegative raw values without floors,
retiming or retries. Primary enclosing clocks remain strictly positive. Historical
execution-only readers retain their original constructor positivity requirements. CSV retains every primary raw call and cache receipt.

Historical v1 fresh-reference and v2 retained-reference execution-only JSON, labels,
clock meanings and readers remain available through frozen schema readers. In
particular v2 constructor/restore/call/drop values and its explicitly named additive
restore-plus-call diagnostics retain their original meaning. They are not rewritten
as full invocations or compared as a source-only speedup. Explicit run/attempt
retrieval may render that history with an execution-only provenance label derived from schema; optional historical
identity.measurement extras cannot promote them to full-call evidence. Default
latest retrieval accepts v3 only: a newest v1/v2 artifact is unavailable for current
full-invocation monitoring and never causes fallback to an older green run.

The canonical JSON validates the exact configured workload/engine/order/sample
matrix, actual native policy, source and host identities before success. Summary
and CSV rendering precede atomic passed publication. Exceptions preserve current
failed evidence and cannot expose an old green table. Per-architecture artifacts
`pvm-performance-<architecture>-<attempt>` retain JSON, CSV, summaries and logs for
30 days, including failure diagnostics; executable images, compiler caches,
private experiments and fixture memory are excluded.

## Retrieve current results

`make pvm-perf-latest` uses authenticated `gh` to locate the newest master-push CI
run and retrieve both native architecture reports. It validates complete scope,
matching measured revision/run identity and each architecture's latest actual PVM
job execution before rendering. Selective retries may leave the two CPUs on different
attempts; both actual attempts remain explicit. Retrying an unrelated job does not
discard valid measurements. A newer failed, cancelled, skipped or incomplete PVM
execution blocks retrieval; an older green execution cannot replace it. The workflow
must finish, and its overall conclusion is shown separately from PVM validity.
The concrete job identity comes from the source-bound report, so display-name changes
need no duplicated selector update. Retrieval never silently substitutes an older
successful revision. Explicit
historical run selection remains available through the helper's `--help` interface.
Downloading reports builds no toolchain and executes no guests.

Local behavioral tests cover scheduling and Make dependency expansion, complete
inventory, clock/policy/ratio validation, failure-safe publication, reference
selection and latest-report retrieval. Native Linux CI on both architectures is the
qualification for actual timing. A sub-resolution local CPU sample is a measurement
failure, not a value to floor, discard or relabel as wall time.

## Current qualification boundary

The shared runtime and this canonical measurement path form one coherent source review unit.
Scoped local Darwin ARM checks passed the supported bound common normal/refusal gates, production
Services lifecycle, the full normal legacy witness, four retained rejection/refusal witness
variants, both region receipt profiles and seven affected unit/golden profiles. These retain real
raw native controls and complete checked histories; they are correctness evidence for those paths.
Nine other mandatory legacy/ownership/arena/policy controls have no matching local qualification
claim and remain required by canonical CI. Actual Linux x86 execution and the final two-job Linux
ARM64/x86-64 comparison on coherent published source are pending.

The common runtime currently admits its implemented pure spans. Connected, memory, resident, wide
and macro features remain unported and their public frame cohorts execute checked. Requested JIT
policy never substitutes for observed native calls or operations. The separately bound native gate
must prove actual supported publication/execution and eligible worker refusal; full-invocation
measurements retain genuine checked fallback without silently inflating work or waiting for it.

The first local pilot on an earlier runtime source stopped at a primary process-CPU window below
clock resolution. Its partial output and failed outcome remain historical failed evidence, not a
current accepted cohort. No local benchmark retry, clock floor, sample discard or wall-time
substitution repairs it. Failure diagnostics retain the actual enclosing CPU/wall observations and
case context, while refusal controls preserve their independent gas sentinel. Actual canonical
Linux runs must report incomplete or zero-primary-clock cohorts as failures. No current v3 timing,
warmed JIT improvement or complete native feature coverage is claimed by these local checks.
