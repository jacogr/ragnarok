# Bound initial-round execution

## Scope and authority

Connect the existing bound service, invocation, machine and dispatcher adapters to complete
initial-round certification. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`: accumulation.tex (accpar/accone), SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
pvm_invocations.tex (accinvocation/collapse), SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`, and pvm.tex,
SHA-256 `b5b4a54ae77aea6b0a599e85d895c377841b89d039206cafc277473bc8f8aa97`.
No protocol equations, pins, codecs or interpreter semantics change.

## Contract

`runBlockAccumulation` accepts a genuine BlockAccumulationRound, immutable explicit chain
parameters and independent local policy. Derive parent state, input service order, header slot
and posterior entropy exclusively through retained block certificates. Check parameter validity,
core count, epoch period, fixed authorization queue length and context population against that
block's profile before guest work. Parameters remain explicit chain configuration, not values
authenticated by the state root. Derive code eligibility from maxServiceCodeSize in those parameters;
preimage copying remains an independent local ceiling.

Bound the complete service count and native descriptor storage before allocations. Resolve each
service in canonical input order, certify missing/malformed/oversized code as zero-gas skips, and
execute ready code through bound invocation, bound context validation, machine initialization and
the real dispatcher. Context validation and dispatch use the same explicit configuration. Each
service starts independently from its original bound parent, not an earlier service's effects.
Engine, host, copy, fetch, provision, probing and account-effect ceilings apply per service; the
service ceiling bounds total work. No caller-authored execution/skip array, entropy, state or slot
is accepted. Existing completeBlockAccumulation alone certifies coverage, collapse, actual gas,
account support and provision union once all guests finish.

Return the existing completed-round owner directly on success. On failure return only typed
reasons, retaining the exact failed dispatcher or completion result where nested reasons exist.
Never expose earlier successful service results or a partial batch. No caller store changes on
success or failure. Halt, panic and either form of out-of-gas are guest outcomes; local engine,
context, backend and policy refusal remain failures. This is deterministic serial evaluation of
independent accpar inputs; it adds no concurrency, continuation loop or full block executor.

## Completion tests

Use real signed admitted fixtures and the existing manual execution/completion path as a parity
oracle. Cover empty and all-skip rounds, mixed execution/skip, halt, checkpoint panic, basic-block
and host out-of-gas, real provisions, exact retained round identity and unchanged original parent.
Exercise invalid round, mismatched parameters/profile, count/copy/initialization/context/fetch/
engine/provision ceilings, late-service refusal and nested batch failure without partial publication.
Test retained success after local sources die; require 1,000 ARC success/failure cycles with stable
occupied storage. Add strict runtime extraction and compiler privacy/nominal guards, source-owned
suite/fixture metadata, inventory and pinned formatting checks.

## Remaining work

M1 framing is complete; full state serialization and accumulation/block parity remain open.
Next bounded work is orchestration of transfer-free continuation/reentry using the retained
completed-round certificates. Transfer-aware recursion, remaining account/privilege effects,
full block execution/validation, persistence and light-node partial-state execution remain open.

## Local verification

Passed `make unit SUITE=accumulation_runner`. Real signed report and allowance rounds agree with
manual service execution/completion for canonical service gas, total gas, skipped coverage and
complete applied-map roots. Covered halt, checkpoint panic, basic-block and host out-of-gas,
empty/all-skip rounds, malformed service framing and parameter-derived oversized code. Real
provide/checkpoint guests agree with the manual terminal union and complete successor root.
The result retains the exact round inputs after local source handles leave scope.

Invalid/default rounds, parameters, core/epoch/queue/population substitutions and service-count
ceilings refuse. Preimage copy, invocation probing, context bytes/missing chapters, envelope
initialization, fetch capture, host copy, provide capture and terminal union ceilings retain their
selected local reasons. Step, host-call and gas-analysis budget failures preserve exact StepError;
a second-service refusal after a successful first guest exposes no partial completion. Separate
code resolution and invocation-seed hash failures preserve their exact backend reasons. The
original admitted maps remain unchanged. No existing interpreter, planner, batch or store behavior
changed; their earlier algorithm/vector and unsupported-effect gate evidence is reused.

The 1,000-cycle real success/late-service-refusal workload retained 736,784 occupied bytes before
and after. Nine strict runtime extraction guards and six compiler privacy/source-type rejections
pass. Python discovery passed 451 tests with seven skips; inventory passed 121 failure families,
1,741 probes and 186 native suites. Pinned formatting and diff checks pass. Evidence is under
ignored `build/accumulation-runner/`; local macOS checks are separate from exact-head Linux CI
and full JAM/STF parity.
