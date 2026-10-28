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
