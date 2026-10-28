# Prepared PVM engine API

## Scope and reference

All engines use the existing immutable `Program`/`Machine`, `PreparedProgram`, `StepResult`
and synchronous `executeWithHost` boundaries. The protocol authority remains the pinned Gray
Paper and the established `pvm-step`, `pvm-execution`, `pvm-host-execution` and
`pvm-polkavm-memory-order` contracts. The optional bridge uses only public PolkaVM APIs at
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`; source/dependency/toolchain pins stay unchanged.
Application and API defaults use the independent `jit` policy; the optional foreign engine never becomes an implicit fallback.

## Ownership and use

`newPreparedProgram(source, limits, selected)` binds one exact immutable source and engine.
The two-argument constructor and zero-initialized invocation policies use `jit`. Explicit `interpreted` binds a plan that cannot emit native handlers even in a JIT-enabled binary.
`preparedInfo(owner).backend` reports the bound engine; completed `StepOutcome.backend`
reports actual execution, including host terminal replies: `jit` means some native work occurred in that invocation, while checked-only independent execution reports `interpreted`. Failed/default results expose no
snapshot or receipt. Identical independently decoded bytes do not authorize another owner.

Prepared handles share one private cache identity with noncopyable composite storage. A busy
lease spans guest execution and every callback; synchronous same-owner reentry returns
`PreparedProgramBusy`. CPU, guest memory, callback contexts and raw pointers never escape
an invocation. The optional foreign instance/module is reused, with RAM/registers/continuation
reset before and after each call and on refusals. Reset failure retires that instance. ARC
releases the exclusive foreign owner after the last prepared handle disappears. Returned
pages are copied into immutable snapshots before instance reuse; unchanged pages remain shared.

Convenience overloads taking `PvmBackend` create the same prepared owner for a single call.
The optional bridge is linked only with `-d:polkavmRuntime`. Ordinary builds return typed
`BackendNotBuilt` at preparation/execution without requiring a Rust library. A JAM decode
profile is required; paper-profile programs return `BackendProgramUnsupported`.

## Exact attempts, gas, hosts and faults

Nim retains the complete unsigned protocol gas balance. Its source-bound bounded lazy price
memo implements the same containing-block charge, prepaid interior entry and repair/retry
rules. Rust receives no protocol gas or callback. Public upstream instruction tracing provides
one source attempt per call; synchronous upstream metering uses private ample `i64::MAX` fuel
replenished for each attempt. That private safety budget never narrows or substitutes for the
unsigned Nim balance. Source-attempt and host-call budgets remain independent and exact.

The same canonical Nim host-response validator enforces causing PC, unsigned gas, register,
memory and action rules. Every prepared reply, including terminal panic/out-of-gas replies,
validates the owner page ceiling before publication and returns `InvalidHostResponse` on refusal.
The same owner remains reusable after rejected replies. One resident foreign instance spans all callbacks. Ordered host
memory changes invalidate its page mappings; protected low-page retained bytes remain solely
in Nim snapshots. Scalar stores track at most two physical page identities; bounded dirty
tracking and existing atomic immutable page replacement publish guest writes.

External gas-plan/memo compatibility overloads remain independent-engine APIs; foreign owners
own their fixed-cycle private memo. Single-step adapters retain their existing scope.
No alternate interpreter is selected after an explicit foreign request.

## Capabilities and qualification

`polkavm-interpreted` is portable on the supported architectures. `polkavm-compiled` currently
requires x86-64 and the pinned Linux sandbox/kernel capabilities. Missing capabilities return
`BackendUnavailable`; loaded revision disagreement returns `BackendRevisionMismatch`.
Compiled preparation also executes a private scratch traced missing-page/repair witness before
accepting application code. Failure returns `BackendCapabilityUnsupported` and no prepared
owner. Arbitrary entry that the public trace API cannot represent returns
`BackendReentryUnsupported`. C ABI errors/unwinds return `BackendFailure`, never a guest panic.
The old unqualified native tracing/paging result from PR1715 is not inherited as a pass.

API/CLI wiring for compiled mode is supported; CI intentionally executes PolkaVM interpreted
only for now. There is no claim of native PolkaVM qualification or optimized compiled throughput.
Tracing prioritizes exact attempts and callback/snapshot semantics. Full validator behavior
and complete JAM parity remain outside this API increment.

## Completion checks

- `make unit SUITE=pvm_runtime_backends`: independent engine, common prepared source/reentry
  and immutable state witnesses, absent optional support.
- `make unit SUITE=pvm_runtime_polkavm`: the same real interpreted guest/host/gas/fault/repair,
  permission/low-page/cross-page and retained-owner witnesses through the linked public ABI.
- The ABI build runs real interpreter traced-paging, reset, layout, invalid-buffer and unwind tests.
- Current Linux CI retains native suite discovery; comparison changes belong to the later stack
  layer and continue to use PolkaVM interpreted as their reference.

The following layers add owner-bound JIT/forced-interpreter policy and CLI selection, then
adapt the existing Linux comparison family without adding a parallel benchmark family.

## Runtime policy and CLI

`--pvm-backend` accepts exactly `jit`, `interpreted`, `polkavm-interpreted` and `polkavm-compiled`.
The option catalog owns help/default presentation; ordinary and dedicated conformance/devnet
commands share strict parsing. Initial/current/later accumulation, authorization, refinement,
download/trace and nested raw machines carry copied selection policy, with no process-global
backend state. The outer refinement selection replaces any conflicting nested policy.

Normal `make` enables our checked ARM64 fragment emitter. `make PVM_POLKAVM=1` explicitly links
the optional bridge and packaging includes its real dependency and upstream licenses. Explicit
foreign requests are checked before application resources open; no alternate engine is selected.
Our JIT currently supports macOS/Linux ARM64. Linux x86-64 uses the same-engine interpreter
fallback and is never reported as native JIT execution. Unsupported operations, refused executable
storage and native code-cache limits retain checked execution.

The immutable private `FlatPlan.allowNative` is captured on every construction path. One cold
emission hook returns before native scanning/allocation when false; the guest dispatch loop
contains no backend-policy branch. Stream transfer requires exact original plan identity, so
native-populated caches cannot enter a forced-interpreted owner. Prepared diagnostics report
requested backend, binary/platform JIT support, fallback policy and cumulative native fragment,
call and operation counters. Busy diagnostic reads return `PreparationError.Busy`; they never
report an empty moved-out cache as zero actual activity. Completed receipts compare invocation
start/end operation counters, including modular wrap, rather than claiming prior native activity.

`pvm_runtime_policy` requires a positive native control on supported ARM64, zero native activity
for forced interpretation through warm reuse and hosts, and both cross-policy cache-transfer
refusals. `pvm_runtime_policy_refused` runs the same witnesses with executable storage refused.
`app_pvm_backend` checks defaults, all names, help, strict malformed/duplicate rejection and
dedicated parsing. `pvm_runtime_application` executes real application/nested dispatch using our
interpreter and PolkaVM interpreted; compiled PolkaVM remains outside CI execution.
