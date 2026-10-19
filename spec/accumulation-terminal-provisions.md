# Terminal-selected accumulation provisions

## Scope and authority

Bind completed PVM accumulation dispatch results to the existing provision union and `fnprovide`
application. Authority remains Gray Paper 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `accumulation.tex` SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f` and
`pvm_invocations.tex` SHA-256 `67a4fa455d2c1e7979ed9eec8849cb2dcdda7386c2f4085f1d11e93e72f7d6cb`.
Use the maintained [terminal normalization](pvm-accumulation-outcome.md) and
[provision union/application](accumulation-provision-integration.md), without replacing their rules.

Preparation accepts completed executions, one explicit candidate slot and existing union ceilings.
Normalize every execution before copying/hashing any provision; retain the actual selected outcome
and require its original invocation slot to match. Halt selects regular effects; panic, physical
fault and out-of-gas select the exceptional checkpoint. Local execution failures and the established
readable-32-byte-halt/nonempty-provisions ambiguity remain typed normalization refusals. Do not
accept substitute contexts, dimension flags, gas facts or caller-created normalized outcomes.

The private immutable plan retains selected outcomes, the union and the checked slot. Application
accepts an explicit posterior complete-map store, uses only the captured slot and delegates atomic
fulfillment to the existing kernel. It does not merge independently credited per-service account
maps, establish a common round/parent, deduplicate execution identities, account total gas, execute
later rounds or certify a complete block transition. Repeated executions remain repeated bounded
contributions; exact provision pairs deduplicate under the existing union contract. An empty batch
is valid with its explicit slot and canonical empty-union budget.

## Completion tests

Use actual guest execution to cover regular halt, checkpoint rollback on panic/fault/out-of-gas,
late normalization failure, readable-32-byte ambiguity and invocation-slot mismatch. Compare exact
fulfilled preimage/history bytes and complete-map roots, including skipped requests, rollback and
no-hash replay. Check default owners, source ordinals, copied input/metadata isolation, exact and
one-short budgets, underlying refusal reasons and retained outcomes after source release. Require
privacy/nominal/runtime extraction guards and 1,000-cycle ARC release. Register new tests using
source-owned verification declarations; no shared runner or inventory edits are needed.

Documented M1 framing completion remains unchanged; full state parity and complete accumulation
publication remain outside this bounded increment.

## API and refusal ordering

`prepareTerminalAccumulationProvisions` first checks the context-count and native descriptor extents.
It normalizes inputs in caller order, verifies each selected context's original service invocation
slot, then invokes the existing bounded union planner. No provision hash is attempted before all
terminal outcomes and slots are accepted. The original normalization reason is available only on
`NormalizationFailure`; `AmbiguousProvisions` remains unchanged. `ProvisionFailure` similarly carries
only the original union/application reason. Neither alternative carries a partial plan or map.

`terminalProvisionInfo` copies the checked slot and union observations. `terminalProvisionOutcomeAt`
uses the existing nominal source ordinal to retain the corresponding immutable normalized outcome.
The plan owns an independent array of outcome handles, so replacing or releasing the borrowed input
sequence cannot change its provenance. `integrateTerminalAccumulationProvisions` accepts no replacement
slot or selected context and delegates to the existing atomic kernel against the explicit posterior
store. Request cancellation and cached-identity replay retain their original semantics.

## Local verification

Passed `make unit SUITE=accumulation_terminal_provisions`, `accumulation_provision_integration`
and `pvm_accumulation_outcome`. The new suite exercises actual halt/panic/fault/out-of-gas programs,
checkpoint versus uncheckpointed rollback, the existing ambiguity gate, slot checks before hashing,
exact/one-short budgets, detached source ownership, copied metadata, cancellation, late malformed
posterior state, write limits, backend rollback and no-hash replay. Its 1,000-cycle ARC workload
retained 421,904 occupied bytes before and after; the two unchanged dependency workloads also
retained their occupied-byte totals.

Nine strict runtime extraction guards and six compiler privacy/nominal rejections passed. The
compiler guards reject arbitrary effect contexts as execution inputs and raw unions as terminal
plans. Source-owned discovery, provenance, pinned formatting and diff checks passed. Python
verification passed 441 tests with six skips. One inline generic-default assertion and one long
conditional test expression were simplified around pinned compiler/formatter behavior; upstream
sources and toolchains remain pristine. Logs are under `build/accumulation-terminal-provisions/`.
These are local macOS results; exact-head Linux CI remains separate.

The [common-source batch coordinator](accumulation-batch-state.md) now verifies a shared immutable
input/prior owner and unique invoking services, merges supported incoming-credit metadata, then
applies this terminal plan on its private candidate. This lower-level API deliberately continues to
accept an explicit posterior store. Complete-round coverage, skipped-service integration,
account-mutating hosts, aggregate gas and block publication remain separate work.
