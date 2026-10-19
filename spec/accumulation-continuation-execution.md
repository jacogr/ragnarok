# Completed continuation execution and gas

## Scope and authority

Bind complete report-only continuation execution/skip coverage and actual service-indexed gas to
`PreparedAccumulationContinuationInputs`. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f` (`accpar`, `accseq`),
pvm_invocations.tex SHA-256 `67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`
(`accinvocation`, collapse), and pvm.tex SHA-256
`b5b4a54ae77aea6b0a599e85d895c377841b89d039206cafc277473bc8f8aa97` (gas affordability).
Pins, domain bytes and the parked namespace question do not change.

Accept only a genuine prepared continuation context, actual completed executions, certified skips
and independent local limits. Derive expected inputs, exact prior snapshot, candidate slot and
posterior entropy from that source. Reject replacement input owners/maps, wrong slots or entropy,
missing/duplicate services and local execution refusals before exposing a completion certificate.
Reuse the complete batch adapter and its existing account-effect compatibility gate. Retain actual
normalized gas once per service in numeric order and prove each addition by remaining-budget
subtraction. Skips use zero gas. Retain source/batch/observations only after all phases succeed;
failed nested results contain reasons alone.

The certificate covers this later round only. Its batch may be applied against its exact retained
prior through the existing atomic full-map adapter; no caller state is published by completion.
Further recursive scheduling/application, transfer recursion, output-set union and final block
publication remain separate integrations. PVM hosts remain unchanged. M1 framing is complete;
full state serialization and accumulation/block parity remain open.

## Completion tests

Use signed ready reports and actual completed initial rounds followed by real later PVM execution.
Verify numeric service gas ordering independently of execution order, consumed-prefix provenance,
no recurring allowance gas, halt/panic/basic-block OOG/host OOG and certified zero-gas skips.
Check empty/all-skip/mixed coverage, copied observations, detached owners, exact/short local limits,
missing/duplicate/invalid outcomes, full-width indices, foreign input/state owners, wrong slot and
entropy, unchanged snapshots and exact-prior batch application/staleness. Exercise hash-disabled
preflight, 1,000 success/refusal ARC cycles, strict runtime result guards and privacy/nominal compiler
rejections. Run the selected suite, Python discovery/inventory and pinned formatting; reuse prior
checks for unchanged owning implementation modules.

## API and ownership

`completeAccumulationContinuation` borrows actual execution/skip arrays and independent
`AccumulationExecutionLimits`. Its genuine source supplies the exact input owner, actual prior
map, authenticated slot and original stage entropy. Service-count/native-row limits precede batch
work; entropy preflight bounds traversal by that service count. The existing complete batch adapter
then validates unique and exhaustive source coverage, slots, terminal selection and supported
account effects. No successful parent result is ever stored in a failed alternative.

Actual gas is taken from the retained normalized batch outcomes, including gas spent before panic
or checkpoint rollback. For each outcome, `consumed <= budget - total` proves both affordability
and representability before adding. Certified skips contribute zero. Numeric service sorting
canonicalizes gas rows independently of caller execution order, while the batch retains its actual
execution order. The copied info preserves selected range coordinates and recursive budget, rather
than reintroducing initial allowances or claiming final recursive accounting.

`executionInfo` and `executionGasAt` return copied observations, with full-width gas ordinals
checked before conversion. `executionBatch` retains the actual complete batch for atomic exact-prior
application. `executionContinuation` retains the original context. The private acyclic certificate
is nominally separate from initial completion: it cannot silently enter an API which assumes an
initial round. Default and refused results expose no source, usable batch, rows or partial gas.

## Verification and remaining work

Passed `make unit SUITE=accumulation_continuation_execution` with fresh maintained-runner ARC
evidence. The 1,000-cycle complete/refused workload retained 1,476,128 occupied bytes before and
after. Pinned formatting and diff checks passed. The signed fixture consumes one report in the initial round and selects the next two-service
report only after actual execution frees gas. Its ordinary continuation budget is 200,956 gas,
with 600 gas reserved in reports and 44 gas actually spent by two halts. Reversing caller execution
order still yields numeric gas rows 42/99 with 22 gas each. Panic consumes 203 gas plus the other
service's 22, unpaid basic-block OOG consumes zero, host debt consumes its entire 200-gas credit,
and genuine skips consume zero. Initialized empty, all-skip and mixed rounds remain distinct from
default owners. Copied observations and detached sources retain their contracts.

Foreign input owners, equal-root cloned maps, original-parent substitution after provision-changing
initial execution, wrong slots/entropy, duplicate/missing services, invalid dispatches/skips,
full-width ordinals and short service limits are rejected. A real initial provision batch changes
the complete successor map before later invocations; only that actual successor can authorize
completion or application. Already-fulfilled requests are correctly suppressed by the host on
later execution, so that later batch is a no-op rather than an artificial backend-failure witness.
Completion/preflight and no-op application pass with hashing disabled. Stale application preserves
the intervening state. Existing provision-fulfillment backend-failure checks remain applicable.

Seven strict runtime extraction guards and six privacy/nominal compiler rejections passed. Python
discovery passed 441 tests with six skips; inventory passed with 104 failure families, 1,561
data-driven probes and 148 native suites. The suite reuses the checksum-verified static report
fixture; no generated corpus setup or runner behavior changes were added. Diagnostic iterations
reuse prepared native libraries; logs remain under `build/accumulation-continuation-execution/`.

Existing batch, initial completion, invocation, service and PVM implementations are unchanged;
prior checks for those owning modules are reused. These are local macOS results, separate from
exact-head Linux CI. The PVM transfer branch was inspected; its host work and the existing selected
account-effect compatibility gate remain untouched. Next work applies a completed continuation
and selects further report-only recursion before transfer-aware scheduling and final output union/
publication. M1 framing remains complete; full serialization and accumulation/block parity remain
open.
