# Bounded report-only execution to a stopped certificate

## Scope and authority

Drive an already completed admitted initial round through continuation and repeated reentry until
an actual n=0 completion. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`: accumulation.tex (accseq/accpar), SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
pvm_invocations.tex (actual gas collapse), SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`.
Existing preparation and real guest execution semantics, pins and domains do not change.

## Contract

`driveAccumulation` accepts CompletedBlockAccumulation, explicit Parameters and
AccumulationDriverLimits. Reuse one AccumulationReentryConfig for bounded selection and
materialization of each later entry, and AccumulationRunnerLimits for each later execution.
The nominal AccumulationReentryDepthLimit caps retained reentry depth, including a terminal
reentry. Zero permits a stopped first continuation only. If continuation selection dispatches,
zero refuses before input/state preparation or guest work. Subsequent depth exhaustion refuses
before preparing or executing the next reentry. Never return a live prefix as completed success.

Use existing selection, private batch application, bound later runners and checked repeated
advance. Each selected batch is executed once; each just-completed batch is applied once by the
next input preparation. Initial guests and older batches are not replayed. Allowances never recur;
report order, whole-report rejection, actual-gas budgets, exact posterior maps, original block
slot/entropy/profile and unsupported-transfer/account/privilege gates remain enforced by their
existing source certificates. No caller supplies an offset, gas total, replacement source map or
outcome arrays. Total work is bounded by one continuation plus at most the configured reentry
depth, with separate per-entry selection/materialization/execution ceilings. A full-width cap is
a policy, never an allocation size; existing checked depth increment remains authoritative.

Return a private StoppedAccumulation alternative retaining exactly the stopped continuation or
reentry certificate. Defaults are Uninitialized; guarded child access cannot confuse either kind
or expose a live completion. This value adds no mutable storage or back-reference to its history.
Preserve failed selection/input/runner/reentry results with all existing nested reason contracts;
failures expose no earlier successful history or partially prepared state. Neither success nor
refusal mutates caller stores. Finalization, chapter composition and publication remain separate.

## Completion tests

Use real signed fixtures and independent manual guest/selection/completion loops. Compare terminal
kind, offsets, pending suffix, actual remaining gas, exact input/source identity, complete final
state roots and outputs through existing finalization. Cover empty, stopped-with-pending,
continuation-only, repeated dispatched reentries plus terminal entry, mixed/all code skips, panic,
both OOG branches, fresh provisions and yield history. Check zero/exact/short/full-width depth,
no bypass of unaffordable reports, short selection/materialization/guest limits, deep nested
failures and late refusal with unchanged original snapshots. Retain both terminal kinds beyond
local sources. Require 1,000 ARC success/refusal cycles, strict result/terminal extraction and
privacy/source/depth nominal guards, source-owned fixture metadata, Python/inventory and pinned
formatting checks.

## Remaining work

Next bounded work connects this stopped driver result to final accumulation and the existing
chapter-composition path. Transfer-aware recursion, remaining account/privilege effects and full
block execution/validation remain open. M1 framing is complete; full state serialization and
accumulation/block parity remain open.

## Local verification

Passed `make unit SUITE=accumulation_driver`. Independent manual selection, real PVM dispatch,
completion and repeated advance agree with the driver's stopped history through existing
finalization: exact offsets, pending suffix, remaining actual gas, output work/count and complete
final-state roots. A seven-report fixture stops at reentry depth four, offset seven and remaining
200,780 gas. Caps one through three refuse rather than return a live prefix; exact four and
full-width caps succeed. Zero accepts stopped continuation and rejects dispatched selection before
hashing or input/state/guest work. Idle continuation after two genuine completed initial guests
also succeeds with hashing disabled and zero hash calls, proving those guests are not replayed.

Covered genuinely empty state work, a stopped three-report pending suffix with an unaffordable
head, one dispatched continuation followed by stopped reentry, mixed/all code skips, checkpoint
panic, both OOG charging branches, fresh provisions and four unique yielded output pairs across
history. Both terminal kinds retain valid detached histories. Original caller snapshot identities
remain unchanged on success, depth exhaustion, preparation and late execution refusal.

Selection/outcome work, operand/input materialization, step/fetch/complete-batch and provide
ceilings preserve exact selected nested reasons. A continuation succeeds before reentry selection
or execution refusal; another fixture executes a live reentry before the next three-operand entry
exhausts its capture budget. Defaults and foreign source families cannot authorize this driver.
The final 1,000-cycle workload includes full histories, idle continuation, depth exhaustion and
late reentry refusal; occupied storage is 1,592,336 bytes before and after.

Nine strict runtime extraction guards and ten compiler privacy/source/depth rejections pass.
Python discovery passed 451 tests with seven skips. Inventory passed 123 failure families, 1,770
probes and 188 native suites; pinned formatting and diff checks pass. Existing selection,
materialization, PVM, private batch application, transfer/account gates and finalization algorithms
are unchanged; their prior vector/algorithm/rejection evidence is reused. Logs remain under
ignored `build/accumulation-driver/`. These are local macOS checks, separate from exact-head Linux
CI and full JAM/STF parity.
