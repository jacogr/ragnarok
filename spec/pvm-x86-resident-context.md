# Resident x86 region invocation bookkeeping

## Scope and hypothesis

Independent draft layer above the qualified ARM profile in stack1786. The parent
is the accepted single-region runtime; no rejected capacity change is restored.
The measured x86 connected-loop profile identifies region wrapper/accounting
work as a major boundary. This trial changes only invocation-local visit and
last-completed-header storage in emitted region code.

Caller-saved XMM0/XMM1 hold exact integer visit counts, XMM2 holds all-one lanes
for PSUBQ integer increments, and R11 holds the complete last-header value. SSE2
is baseline x86-64. Ordinary emitted bodies use only RAX/RCX/RDX/R8; gas/quota
remain in R9/R10. Every guarded/external return writes the same five-word scalar
context once. Zero-block returns preserve the complete incoming endpoint sentinel.
No pointer survives a call. Guest register access, source/gas guards, checked
memory, admission/hotness, quotas, handler policies and code-owner ABI are unchanged.

The original arithmetic/conditional emitters and checked fallback remain intact.
There is no FP arithmetic, optional ISA, new store/read lowering or ARM runtime
change. The context's exact integer visits remain bounded by source attempts;
each admitted block consumes at least two attempts before incrementing its count.

## Qualification and decision

The maintained CI qualifier adds1,440 independent scalar context cases across
one/two blocks, zero/partial/large quotas and gas, overflow-edge guest values and
full-width incoming sentinels. It compares all thirteen guest registers, gas,
remaining attempts, both visit counts, final endpoint and exact returned target.
Existing native/refused opcode, source-prefix, host/memory and owner controls remain.
All native compilation, execution and timing remains CI-only.

Keep only qualified same-runner useful paired gains without material regressions;
otherwise restore only the runtime emitter delta while retaining useful witnesses
and rejection evidence. Constructors, cold/reused public calls, retained-core
lifecycle and reference restoration remain separate. Both process orders and
complete source/state/image/compiler seals are required. No timing claim yet.

The manual x86 profiling target explicitly selects sealed baseline/current roles
for this trial, retaining the same sieve/Pinky/gameplay scopes and thirteen exact
return dumps. Direct profiler callers keep their interpreter/current default
unless `--paired-baseline` is supplied. The cohort still includes interpreted
policy and PolkaVM timings; paired profiles isolate the runtime emitter delta.
