# PVM interpreter readiness and next comparison boundaries

## Authority and scope

Gray Paper 0.8.0 (`07f041dabd073f9018b418e9ee72e79dd2185401`) remains primary.
PolkaVM 0.37.0 (`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`) is the pinned
public-API implementation cross-check. No pins or semantic decisions change here.
This map reconciles older increment descriptions with implemented contracts;
individual feature documents retain their original observations and limitations.

## Implemented interpreter boundaries

| Boundary | Contract and focused checks |
| --- | --- |
| Owned decoding | [Program](pvm-program.md): all opcode/operand shapes, malformed framing, immutable input ownership; [operand matrix](pvm-operand-reference.md) checks 62,550 cases through the public parser and both native profiles. |
| Register mutations | [Registers](pvm-registers.md): all 85 register opcodes; [validated-result reuse](pvm-validated-register-evaluation.md) replays 38,977 independent rows through both evaluator entry points. |
| Gas and control | [Gas](pvm-gas.md), [block boundaries](pvm-gas-block-boundaries.md), [conditional control](pvm-conditional-control-reference.md) and [load/jump](pvm-load-jump-reference.md): independent pipeline prices, local work ceilings, target validity and aliased register mutations. |
| Memory and retry | [Memory](pvm-memory-access-reference.md), [boundary ordering](pvm-memory-boundary-reference.md), [metered retry](pvm-metered-fault-retry-reference.md) and [cross-page retry](pvm-cross-page-metered-retry.md): permissions, protected/absent pages, wraparound, paid retries and immutable source snapshots. |
| Execution and hosts | [Execution](pvm-execution.md), [host dispatch](pvm-host-execution.md), [fallible replies](pvm-host-failures.md) and [mixed programs](pvm-mixed-program-reference.md): recursive exits, shared budgets, repeated host continuations and complete CPU/memory outcomes. |
| Initialization and output | [Standard initialization](pvm-initialization.md), [output](pvm-output.md), [module bounds](pvm-module-limits.md) and [final terminators](pvm-final-terminator-validation.md): scoped JAM preparation, arguments, page layout and return-buffer extraction. |

The scoped [authorization invocation](pvm-authorization-invoke.md),
[inner invocation](pvm-inner-invoke.md) and
[accumulation integration](pvm-accumulation-integration.md) contracts exist above
these boundaries. They retain independent host, state, provenance and specification
gates. Their existence must not become a blanket claim that every JAM invocation
or host function has complete parity.

## Reproducible evidence and access

`make check-pvm-reference` discovers each Rust probe's source-owned declaration,
checks pinned inputs and runs its matching native suite. The latest local runtime
increment passes all fourteen declared pairs. This is targeted deterministic
comparison, not a universal state adapter or the complete upstream test suite.
Some backend-neutral probes inspect parsing/gas simulation rather than execution.
Raw paper-only behavior and local resource policies retain their separate verdicts.

The [Linux reference job](pvm-reference-ci.md) can be selected with Actions → CI →
Run workflow → `pvm-reference`. Its Actions summary and artifact preserve per-pair
verdicts. A recorded exact-head Linux run at
`bb3ec585b4489abfdaa1dd8b48feaab56873f5d5`
([run 39595533184](https://github.com/jacogr/ragnarok/actions/runs/39595533184))
passes all fourteen pairs. This predates validated-result reuse and does not claim
Linux verification of later runtime changes.

`make bench-pvm` validates complete outputs before accepting timing samples.
Actions → CI → Run workflow → `bench-pvm` publishes the consolidated comparison
in the run summary, with JSON, CSV, Markdown and logs in the downloadable artifact.
Only Ragnarök and PolkaVM interpreted execute; compiled cells remain **Deferred**
by maintainer decision. Preparation is separate from timed execution. See the
[benchmark contract](pvm-benchmark-comparison.md) for fixed workloads, metadata,
noise flags and raw-sample policy. Local speed changes do not establish Linux or
whole-client throughput improvements.

## Open gates and next work

- Keep every [Gray Paper discrepancy/ambiguity](graypaper-discrepancies.md)
  traceable to exact pinned text, an original witness and a scoped compatibility
  decision. An implemented exception does not clarify the paper itself.
- The positive `gas` versus `signedgas` domain mismatch remains explicitly open in
  [host gas accounting](pvm-host-gas.md#exact-terminal-balances). Current full uint64
  nonnegative inputs are retained; no silent signed narrowing is authorized.
- Broaden composition coverage across different arithmetic operations and block
  transitions, then profile the resulting interpreter costs. Existing operation
  matrices and short fixed loop guests do not prove arbitrary program equivalence.
- Add the [required full upstream PolkaVM differential fuzzing job](graypaper-discrepancies.md#required-future-polkavm-fuzzing-ci)
  separately when a faithful state adapter and reproducible failure handling exist.
  Current deterministic comparisons and malformed-input native tests do not satisfy it.
- Revisit compiled performance only after the interpreted baseline is competitive;
  the [pinned compiled host-API failure](pvm-compiler-final-page.md) stays documented.
- M1 framing is complete. Full state serialization, whole-block parity and full
  chainspec equivalence remain open and are not established by interpreter tests.

## Documentation verification

Check every changed local Markdown target, the named Make/workflow selectors and
source-owned reference declarations. This documentation increment changes no runtime,
fixture or compiler inputs; preceding focused native/benchmark evidence is reused,
without claiming a fresh execution or closing any gate.
