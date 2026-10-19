# Bound reentry invocations and completed execution

## Scope and authority

Bind prepared accumulation reentry to actual Psi_A invocation and complete execution/skip coverage.
Authority remains GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex SHA-256 `bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`
(`accseq`, `accpar`), pvm_invocations.tex SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb` (`accinvocation`, `I`, collapse)
and pvm.tex SHA-256 `b5b4a54ae77aea6b0a599e85d895c377841b89d039206cafc277473bc8f8aa97`
(gas affordability). Pins, domains and the parked namespace question do not change.

Resolve only the exact reentry inputs, actual complete successor and authenticated slot. Derive
posterior entropy from the retained original block stage, never the parent/account map. Reuse the
existing seed, compact argument, code eligibility and collision-probe contracts. Retain immutable
source/projection certificates only after complete success; no caller supplies replacement entropy,
service, slot, inputs or state to the bound constructor.

Complete only exhaustive unique execution/certified-skip coverage from that exact reentry owner.
Validate stage entropy and reuse the complete batch adapter for source/state/slot/terminal selection
and supported account effects. Retain canonical numeric service gas rows, adding actual consumption
only after remaining-budget subtraction proves both affordability and representability. Skips use
zero gas. Failed/default results retain only selected reasons, including genuinely refused batch
parents. Completion itself neither applies its new batch nor publishes caller state.

This layer certifies reentry execution. Repeated scheduling/application, transfer-aware recursion,
output union and final publication remain subsequent work. PVM hosts and selected-account gates
remain unchanged. M1 framing is complete; full serialization and accumulation/block parity remain
open.

## Completion tests

Use signed four-report fixtures with genuine completed initial/later rounds and actual reentry
PVM runs. Distinguish posterior from parent entropy; verify literal compact arguments, code/PC/gas,
exact state/input identity, cumulative offsets, copied observations and detached ownership.
Exercise halt/panic/basic-block OOG/host OOG, mixed/all-skip/empty/stopped cases, numeric gas order,
wrong entropy/slot, equal-root foreign maps, re-prepared input owners, missing/duplicate/invalid
coverage, full-width ordinals and independent limits. Include actual provision-changing reentry
state and reject its old prior. Verify hash-free preflight/no-op application, exact-prior staleness,
strict extraction/privacy/nominal probes and 1,000 ARC cycles. Run selected native/Python/inventory
checks and pinned formatting, reusing prior unchanged owning-module results.

## API and ownership

`prepareReentryAccumulationInvocation` takes a genuine prepared reentry, nominal service ordinal,
service policy and collision-probe cap. It resolves only that source's exact input/map/slot and
follows retained completions to the original authenticated block stage's exact 128-byte C(6).
Only its posterior entropy word feeds the existing bootstrap. The private acyclic bound owner
retains reentry plus projection; `bootstrapReentry` and `bootstrapProjection` retain those owners
independently. Service and invocation refusals carry enum reasons behind their corresponding
extraction contracts. No foreign module's private result fields are constructed.

`completeAccumulationReentry` borrows actual dispatch/skip arrays and existing independent execution
limits. Complete row-extent limits precede batch work, and entropy preflight is bounded by the
expected service count. The existing complete batch adapter validates exhaustive unique input
coverage, exact input/prior owners, candidate slots, terminal selection and account-effect support.
Actual gas comes only from its retained normalized outcomes. Remaining-budget subtraction proves
all additions; skips add zero. Gas rows sort numerically, while batch outcomes retain caller order.

`executionInfo` and `executionGasAt` return copied range/gas facts, with full-width ordinal checks.
`executionReentry` and `executionBatch` retain exact source and complete batch for future integration
and existing atomic exact-prior application. Only successful certificates retain these owners;
failed batch alternatives retain actually refused parents and their nested reason contracts.
`CompletedAccumulationReentry` remains nominally distinct from earlier continuation completion,
so it cannot silently enter an API which assumes the earlier source shape.

## Local witnesses and limits

The signed queue consumes report 64 initially and report 65 in the completed continuation. Reentry
selects reports 66/67 for services 42/99 with cumulative completed offset 2, selected count 2,
200,912 recursive budget and 2,000 declared gas. Service 42 receives two operands and literal compact
arguments `[2, 42, 2]`; its own selected code initializes at PC 5 with 1,000 gas. Posterior block
entropy is explicitly different from the parent/account map and determines the next-service seed.
Copied arguments and metadata cannot mutate later observations.

Real halts use 22 gas each, with canonical rows independent of reversed caller order. Panic retains
203 gas plus the other service's 22; unpaid basic-block OOG uses zero and host debt consumes the
whole 200-gas credit. Genuine missing-code skips use zero, including mixed/all-skip sources.
Initialized empty and stopped reentries complete with zero services rather than becoming default
owners. The bounded test runner captures both service-42 operands, avoiding the older one-input
fixture cap without changing its existing consumers.

Coverage rejects foreign input owners, equal-root cloned maps, wrong slot/entropy, invalid/default
outcomes, duplicate/missing services, full-width ordinals and short row limits. A real initial OOG
followed by later provide execution changes the actual full map before reentry; both bootstrap and
completion bind to that successor and reject the old map with the same input owner. Hash-disabled
preflight/no-op application and exact-prior staleness preserve original/intervening snapshots.
Detached sources and input arrays do not invalidate retained bootstrap/completion graphs.

Passed `make unit SUITE=accumulation_reentry_execution` with fresh maintained-runner evidence.
The 1,000-cycle bootstrap/completion success/refusal workload retained 2,007,504 occupied bytes
before and after. Python discovery passed 441 tests with six skips; inventory passed with 106
failure families, 1,585 data-driven probes and 150 native suites. Pinned formatting and diff checks
passed.

Thirteen strict runtime extraction guards and twelve privacy/nominal compiler rejections passed.
The shared new four-report fixture supports later integrations without repeating signed setup in
each new test. The selected suite reuses the checksum-verified static report witness; no generated
corpus dependency or runner behavior change was added. Existing production batch, service, machine,
dispatch and earlier completion implementations are unchanged; their prior checks are reused.

Logs remain under `build/accumulation-reentry-execution/`. These are local macOS results, separate
from exact-head Linux CI. New PVM query/solicit work was inspected; host work and account-effect
gates are unchanged. Next work connects completed reentry to repeated report-only scheduling and
application, then output union/final publication. Transfer-aware recursion remains gated. M1 framing
is complete; full state serialization and accumulation/block parity remain open.

Efficiency note: reentry's two-operand group requires its own finite capture policy; the older
one-input runner remains unchanged. The pinned formatter can remove binary-operator spacing when
wrapping long chained assertions, even after output stabilizes. Store long call results in named
locals, format, then compile against prepared native libraries before the maintained launcher.
This avoids repeating dependency setup for formatting-only diagnostics. No compiler/dependency
patch or assertion weakening was used.
