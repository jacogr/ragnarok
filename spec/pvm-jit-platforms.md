# Native JIT default build selection

Scope: select the existing independent emitter in ordinary peer builds on the maintained host
matrix. The Gray Paper, `pvm-execution`, `pvm-handler-stream` and `pvm-x86-jit` semantics remain
unchanged. There is no new evaluator, public engine identity or toolchain/dependency upgrade.

| Host | Native build define |
|---|---|
| Linux x86-64 | `pvmX86Jit` |
| Linux ARM64 | `pvmArm64Jit` |
| macOS ARM64 | `pvmArm64Jit` |
| Other OS/CPU pairs | Neither; checked interpreter fallback |

The public default was already `jit`; the production builder now includes the corresponding
backend using the same pure `native_defines` plan as the real CLI comparison driver. Explicit
`--pvm-backend interpreted` disables native preparation/execution. Unsupported operations,
partial budgets and executable-storage refusal keep checked same-engine fallback. Optional
PolkaVM engines retain their explicit independent selection and do not substitute silently.
Library consumers still select their desired native compile define explicitly.

Ordinary native Linux CI runs the corresponding x86/ARM positive/refusal, opcode, memory/host,
source-prefix and ownership gates. Existing ARM-only public-policy tests additionally retain
an unavailable-backend control on x86; the x86-specific qualification runs positive and refused
public policies with its genuine native flag. The PVM Comparison job uses public JIT/interpreter
application cohorts on both Linux architectures. Baseline receipts record a controlled matching
native build where the source provides that backend, and checked fallback for older x86 sources;
this is not a claim that an opt-in historical backend was that revision's shipped default.

Real CLI-selected continuing DOOM parity must prove native execution on both supported Linux
architectures and match PolkaVM interpreted frame bytes/hashes, complete state/gas and ordered
host events. Existing mutation/refusal controls remain required. All native compilation,
execution, performance and profiling stay on CI during this work.

Status: build/CI integration prepared; native platform qualification, real continuing-frame
checks and final timings are pending. Default readiness recommendation remains held while
its isolated x86 admission/performance parent is qualified. Passing local Python flag-plan,
workflow and receipt-parser tests is not native execution evidence. No PR merge is authorized.


## Exact-head production and continuing-frame qualification

[Run40691521892](https://github.com/jacogr/ragnarok/actions/runs/40691521892) at
`0031e64cdd6066f56471011303d4bf647605c1ec` passes real CLI-selected continuing DOOM on both
native Linux architectures. Both calls report actual `jit`, with positive compilation/execution
counters and supported native flags. All state, gas, ordered host-event and RGBA hashes match
PolkaVM interpreted, and the same two distinct frame hashes match across both architectures.
Six mutation/refusal controls pass per architecture. Independent source/build/raw-log audits
verify the exact compiler pin, expected native define and recorded outputs.

Frame RGBA SHA256 values:

- `44f42f5bed248db9caadf2caf329a2857e1c54a084b69d6b44fba83df4e5422b`
- `ce5f398853f8fb00db2e01c84e3248a08bd716ad2dae3fccba3591e64b3e2ce1`

[Run40692892088](https://github.com/jacogr/ragnarok/actions/runs/40692892088) at that same head
passes the real checked production builds, packaging and relocated-peer smoke tests for
Linux/Docker and macOS. Native engine/runtime sources, production flag selection and CLI driver
remain identical after subsequent documentation/report-formatting changes; measured-head
provenance is retained rather than claiming a new executable test from documentation alone.

The ordinary comparison report now retains constructor/cold/reused scopes, retained-core reset
and immutable publication, reference restoration/teardown and software native/source counters.
The formatter has been exercised against seven complete retained cohorts without running native
code locally. Final ordinary two-architecture PVM comparison remains pending.
