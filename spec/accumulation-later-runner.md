# Execute prepared continuation and reentry rounds

## Scope and authority

Connect genuine report-only continuation and reentry input certificates to real guest execution
and their existing complete-round adapters. Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`: accumulation.tex (accseq/accpar/accone), SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
pvm_invocations.tex (accinvocation/collapse), SHA-256
`67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`, and pvm.tex,
SHA-256 `b5b4a54ae77aea6b0a599e85d895c377841b89d039206cafc277473bc8f8aa97`.
No equations, pins, domains, codecs or interpreter behavior change.

## Contract

`runAccumulationContinuation` takes PreparedAccumulationContinuationInputs and returns the existing
CompletedAccumulationContinuation. `runAccumulationReentry` takes PreparedAccumulationReentry and
returns the existing CompletedAccumulationReentry, at any prepared depth. Both accept explicit
Parameters and reuse AccumulationRunnerLimits. Derive the original block profile through direct
root provenance. Validate parameters/core/epoch/fixed queue length and context cardinalities even
for stopped input sets. Bound service descriptors before work. Derive code eligibility from the
parameters and apply independent local copying/engine/effect ceilings per service.

Resolve each service in canonical input order from the source's exact inputs and actual complete
posterior map, never the original admitted map or an earlier guest's effects. Missing, malformed
and oversized code use certified skips. Ready code uses the existing bound later-invocation
adapters to derive original block slot and posterior block entropy, then prepares contexts and a
real machine and executes the dispatcher. No caller-authored outcomes, replacement state, slot,
entropy, inputs or recurring allowances/transfers are accepted. Existing complete-round adapters
alone certify coverage, supported account effects, terminal unions and actual gas.

Success retains the completed source graph. Failure retains only selected typed reasons, including
exact failed dispatcher and continuation/reentry completion results where nested reasons exist;
no earlier successful guest, partial batch or state escapes. Default results refuse extraction.
Both paths preserve caller snapshots and existing transfer/account/privilege gates. Stopped
prepared entries complete with zero guests/gas; completed stopped reentries cannot restart under
the existing preparation rules. Serial evaluation of one independent round adds no recursion loop,
new selection algorithm, finalization, publication, persistence or light-node execution.

## Completion tests

Compare real signed continuation and reentry fixtures against manually executed guests and existing
completion adapters: exact source identity, service/total actual gas, skip coverage and complete
successor roots. Cover halt, checkpoint panic, basic-block/host OOG, mixed/all skips, stopped/empty
entries, actual provision-changing posterior maps, repeated reentry depths and stopped advance.
Check invalid/default sources, profile mismatch, nominal source separation, full local descriptor,
preimage/probe/context/initialization/fetch/engine/effect bounds, late-service refusal and nested
completion reasons without caller mutation. Retain results after source scopes die. Require 1,000
ARC success/refusal cycles, strict extraction/privacy/nominal guards, source-owned suite/fixture
registration, Python/inventory and pinned formatting checks.

## Remaining work

Next bounded work is a depth-bounded driver from initial completion through report-only continuation
and repeated reentry to a stopped certificate. Transfer-aware recursion, remaining account/privilege
effects and full block execution/validation remain open. M1 framing is complete; full state
serialization and accumulation/block parity remain open.

## Local verification

Passed `make unit SUITE=accumulation_later_runner`. Both paths match manually composed real
bound invocations/completion for service and total gas, skip coverage and complete applied-map
roots. Covered checkpoint panic, both OOG charging branches, mixed/all skips, parameter-derived
oversized-code skips, empty/stopped sources and four genuine reentry depths ending in a stopped
entry. That completed entry refuses further advance. Exact original input owners are retained;
both completion families outlive local source handles.

Provision-changing posterior maps remain the actual service prior. Executing the retained earlier
continuation with still-outstanding requests produces the same complete root as the existing
manually fulfilled reentry source. Zero capture/copy/union policies refuse with the exact
selected dispatcher or nested batch/provision reason. Profile substitutions, service descriptors,
preimage copying, probing, contexts, machine initialization, fetch capture and separate step/gas
analysis ceilings refuse without publishing partial rounds. Each source path preserves immediate
service backend failure and a later invocation-seed backend failure. A second-service engine
refusal after the first guest succeeds exposes no earlier successful result. Original snapshots
remain immutable.

The final 1,000-cycle workload runs successful continuation and reentry plus late-service refusals
on both paths; occupied storage remains 1,562,848 bytes before/after. Twenty strict runtime
extraction guards (both concrete public result instantiations) and seven compiler privacy/nominal
rejections pass. Python discovery passed 451 tests with seven skips. Inventory passed 122 failure
families, 1,761 probes and 187 native suites; pinned formatting and diff checks pass. Earlier
interpreter, source preparation, transfer/account gates and complete-map algorithms are unchanged,
so their existing algorithm/vector and rejection evidence is reused.

A reduced semantic check isolated an internal pinned-compiler assertion involving a nested template
inside a generic helper. Direct returns and private concrete source dispatch avoid that pattern;
public source types and guarded results remain strict. The toolchain and upstream sources were
not changed. Diagnostic reductions and verification logs remain under ignored
`build/accumulation-later-runner/`. These are local macOS results, separate from exact-head Linux
CI and full JAM/STF parity.
